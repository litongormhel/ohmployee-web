-- ============================================================================
-- Migration: 20262906000003_coverage_add_store_propagation_fix.sql
-- Created:   2026-06-29
-- Author:    Antigravity (ohm#4q8z2m7a) — continuation from Claude session limit
-- Purpose:   Permanent engine fix + generic reconciliation for Coverage Group
--            Add Store propagation failures.
-- ============================================================================
--
-- ROOT CAUSES CONFIRMED (Claude audit, ohm#4q8z2m7a):
--
--  BUG 1 — add_store inner loop: no ELSE branch for live employees.
--    When a CG-promoted live employee (source_employee_import_batch_id IS NULL
--    AND source_baseline_import_batch_id IS NULL) is in the target Coverage Group,
--    the Add Store execution loop only handles imported employees. Live employees
--    get no plantilla_store_links row and no employee_store_allocations row.
--    Result: Employee Stores tab stays stale after Add Store.
--
--  BUG 2 — fn_sync_employee_store_allocations: no-op for CG roving employees.
--    The footprint queries require:
--        deployment_type = 'Roving' AND roving_assignment_id IS NOT NULL
--    Coverage Group promotions set coverage_group_id + coverage_slot_id
--    but leave roving_assignment_id = NULL and vcode = NULL.
--    The stationary fallback also fails (requires vcode IS NOT NULL).
--    Result: fn_sync_employee_store_allocations falls through silently and
--            produces no ESA rows for Coverage Group roving employees.
--
--  BUG 3 — HC share never recomputed in Add Store branch.
--    fn_recompute_cg_hc_shares(p_coverage_group_id) is never called after a
--    successful Add Store execution.
--    Result: coverage_group_stores.hc_share is stale after Add Store.
--
--  BUG 4 — Historical CGs may already be inconsistent.
--    Stores were added before this fix. ESA rows, plantilla_store_links, and
--    hc_share are all potentially stale for any CG that had Add Store executed
--    prior to this migration.
--    Result: Requires idempotent generic reconciliation that can repair any CG.
--
-- IMPLEMENTATION:
--  §1  Patch fn_sync_employee_store_allocations — add Coverage Group roving footprint
--  §2  Patch _execute_approved_coverage_request — add_store ELSE branch (live employees)
--      and call fn_recompute_cg_hc_shares at end of add_store
--  §3  NEW fn_reconcile_coverage_group(uuid) — idempotent per-CG repair
--  §4  NEW fn_reconcile_all_coverage_groups() — idempotent full repair
--  §5  Pre-reconciliation audit
--  §6  Run reconciliation once
--  §7  Confirm no-op on second run
--
-- ADR-001 COMPLIANCE:
--  - Coverage Request never creates slots, vacancies, or HC (unchanged)
--  - Slot-first architecture preserved
--  - No duplicate slots, no duplicate ESA rows, no duplicate store links
--  - Vacancy suppression logic untouched
--  - RLS not weakened
--  - No Flutter changes required
-- ============================================================================

BEGIN;

-- ============================================================================
-- §1  Patch fn_sync_employee_store_allocations
--     Add Coverage Group roving footprint branch:
--       deployment_type = 'Roving' AND coverage_group_id IS NOT NULL AND roving_assignment_id IS NULL
--     These employees have active plantilla_store_links with coverage_group_id set.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_sync_employee_store_allocations(p_employee_no text)
  RETURNS numeric
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_has_live   boolean;
  v_cnt        integer;
  v_each       numeric(8,4);
  v_remainder  numeric(8,4);
  v_first_id   uuid;
  v_total      numeric;
BEGIN
  IF p_employee_no IS NULL THEN
    RETURN NULL;
  END IF;

  -- Early guard: do nothing (and never touch import rows) for an employee that
  -- has neither a LIVE occupying master nor any LIVE allocation to clean up.
  SELECT
    EXISTS (
      SELECT 1 FROM public.plantilla m
       WHERE m.employee_no = p_employee_no
         AND m.is_deleted = false
         AND COALESCE(m.is_archived, false) = false
         AND m.status IN ('Active','On Leave','For Deactivation','Pending Deactivation')
         AND m.source_employee_import_batch_id IS NULL
         AND m.source_baseline_import_batch_id IS NULL
    )
    OR EXISTS (
      SELECT 1 FROM public.employee_store_allocations a
       WHERE a.employee_no = p_employee_no
         AND a.is_active
         AND a.source_import_batch_id IS NULL
    )
  INTO v_has_live;

  IF NOT v_has_live THEN
    RETURN NULL;
  END IF;

  -- ── Deactivate LIVE active allocations no longer in the desired footprint ──
  WITH masters AS (
    SELECT m.id AS plantilla_id, m.deployment_type, m.roving_assignment_id,
           m.store_id, m.vcode, m.store_name, m.account_id, m.hr_emploc_id,
           m.coverage_group_id
    FROM public.plantilla m
    WHERE m.employee_no = p_employee_no
      AND m.is_deleted = false
      AND COALESCE(m.is_archived, false) = false
      AND m.status IN ('Active','On Leave','For Deactivation','Pending Deactivation')
      AND m.source_employee_import_batch_id IS NULL
      AND m.source_baseline_import_batch_id IS NULL
  ),
  footprints AS (
    -- Roving via legacy roving_assignment_id: one per active store link
    SELECT m.plantilla_id, psl.vcode, psl.store_name,
           NULL::uuid AS store_id_hint, NULL::uuid AS account_id_hint
    FROM masters m
    JOIN public.plantilla_store_links psl
      ON psl.plantilla_id = m.plantilla_id
     AND psl.status = 'Active'
     AND psl.deleted_at IS NULL
    WHERE m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL
    UNION ALL
    -- Roving via legacy roving_assignment_id: HR Emploc store-link fallback
    SELECT m.plantilla_id, hsl.vcode, hsl.store_name,
           NULL::uuid AS store_id_hint, NULL::uuid AS account_id_hint
    FROM masters m
    JOIN public.hr_emploc_store_links hsl
      ON hsl.deleted_at IS NULL
     AND hsl.status = 'Confirmed'
     AND (
       hsl.hr_emploc_id = m.hr_emploc_id
       OR hsl.roving_assignment_id = m.roving_assignment_id
     )
    WHERE m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL
    UNION ALL
    -- ── NEW: Coverage Group roving (coverage_group_id IS NOT NULL, roving_assignment_id IS NULL) ──
    -- Source: plantilla_store_links keyed by coverage_group_id (set during CG promotion).
    -- Resolves store_id via stores.vcode match since psl.vcode holds the store's VCode.
    SELECT m.plantilla_id, psl.vcode, psl.store_name,
           s.id AS store_id_hint, m.account_id AS account_id_hint
    FROM masters m
    JOIN public.plantilla_store_links psl
      ON psl.plantilla_id = m.plantilla_id
     AND psl.coverage_group_id = m.coverage_group_id
     AND psl.status = 'Active'
     AND psl.deleted_at IS NULL
    LEFT JOIN public.stores s ON upper(s.vcode) = upper(psl.vcode) AND s.is_active = true
    WHERE m.deployment_type = 'Roving'
      AND m.coverage_group_id IS NOT NULL
      AND m.roving_assignment_id IS NULL
    UNION ALL
    -- Stationary / pool: the master itself (keyed by its vcode)
    SELECT m.plantilla_id, m.vcode, m.store_name,
           m.store_id AS store_id_hint, m.account_id AS account_id_hint
    FROM masters m
    WHERE NOT (m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL)
      AND NOT (m.deployment_type = 'Roving' AND m.coverage_group_id IS NOT NULL AND m.roving_assignment_id IS NULL)
      AND m.vcode IS NOT NULL
  ),
  resolved AS (
    SELECT DISTINCT ON (f.plantilla_id, upper(f.vcode))
           f.plantilla_id, f.vcode
    FROM footprints f
    WHERE f.vcode IS NOT NULL
  )
  UPDATE public.employee_store_allocations esa
     SET is_active = false,
         effective_end = CURRENT_DATE
   WHERE esa.employee_no = p_employee_no
     AND esa.is_active
     AND esa.source_import_batch_id IS NULL
     AND NOT EXISTS (
       SELECT 1 FROM resolved r
       WHERE r.plantilla_id = esa.plantilla_id
         AND upper(r.vcode) = upper(esa.vcode)
     );

  -- ── Insert allocations for desired footprints not already active ───────────
  WITH masters AS (
    SELECT m.id AS plantilla_id, m.deployment_type, m.roving_assignment_id,
           m.store_id, m.vcode, m.store_name, m.account_id, m.hr_emploc_id,
           m.coverage_group_id
    FROM public.plantilla m
    WHERE m.employee_no = p_employee_no
      AND m.is_deleted = false
      AND COALESCE(m.is_archived, false) = false
      AND m.status IN ('Active','On Leave','For Deactivation','Pending Deactivation')
      AND m.source_employee_import_batch_id IS NULL
      AND m.source_baseline_import_batch_id IS NULL
  ),
  footprints AS (
    SELECT m.plantilla_id, psl.vcode, psl.store_name,
           NULL::uuid AS store_id_hint, NULL::uuid AS account_id_hint
    FROM masters m
    JOIN public.plantilla_store_links psl
      ON psl.plantilla_id = m.plantilla_id
     AND psl.status = 'Active'
     AND psl.deleted_at IS NULL
    WHERE m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL
    UNION ALL
    SELECT m.plantilla_id, hsl.vcode, hsl.store_name,
           NULL::uuid AS store_id_hint, NULL::uuid AS account_id_hint
    FROM masters m
    JOIN public.hr_emploc_store_links hsl
      ON hsl.deleted_at IS NULL
     AND hsl.status = 'Confirmed'
     AND (
       hsl.hr_emploc_id = m.hr_emploc_id
       OR hsl.roving_assignment_id = m.roving_assignment_id
     )
    WHERE m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL
    UNION ALL
    -- ── NEW: Coverage Group roving ──
    SELECT m.plantilla_id, psl.vcode, psl.store_name,
           s.id AS store_id_hint, m.account_id AS account_id_hint
    FROM masters m
    JOIN public.plantilla_store_links psl
      ON psl.plantilla_id = m.plantilla_id
     AND psl.coverage_group_id = m.coverage_group_id
     AND psl.status = 'Active'
     AND psl.deleted_at IS NULL
    LEFT JOIN public.stores s ON upper(s.vcode) = upper(psl.vcode) AND s.is_active = true
    WHERE m.deployment_type = 'Roving'
      AND m.coverage_group_id IS NOT NULL
      AND m.roving_assignment_id IS NULL
    UNION ALL
    SELECT m.plantilla_id, m.vcode, m.store_name,
           m.store_id AS store_id_hint, m.account_id AS account_id_hint
    FROM masters m
    WHERE NOT (m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL)
      AND NOT (m.deployment_type = 'Roving' AND m.coverage_group_id IS NOT NULL AND m.roving_assignment_id IS NULL)
      AND m.vcode IS NOT NULL
  ),
  resolved AS (
    SELECT DISTINCT ON (f.plantilla_id, upper(f.vcode))
           f.plantilla_id,
           f.vcode,
           COALESCE(f.store_id_hint, st.id, va.store_id)        AS store_id,
           COALESCE(st.store_name, f.store_name)                AS store_name,
           COALESCE(f.account_id_hint, st.account_id, va.account_id) AS account_id,
           COALESCE(st.group_id, acc.group_id)                  AS group_id
    FROM footprints f
    LEFT JOIN LATERAL (
      SELECT s.id, s.store_name, s.account_id, s.group_id
      FROM public.stores s
      WHERE upper(s.vcode) = upper(f.vcode) AND s.is_active = true
      ORDER BY s.created_at
      LIMIT 1
    ) st ON true
    LEFT JOIN LATERAL (
      SELECT v.store_id, v.account_id
      FROM public.vacancies v
      WHERE v.vcode = f.vcode
      ORDER BY v.created_at
      LIMIT 1
    ) va ON true
    LEFT JOIN public.accounts acc
      ON acc.id = COALESCE(f.account_id_hint, st.account_id, va.account_id)
    WHERE f.vcode IS NOT NULL
  )
  INSERT INTO public.employee_store_allocations (
    plantilla_id, employee_no, roving_group_id,
    store_id, vcode, store_name,
    account_id, group_id,
    filled_hc, active_store_count,
    effective_start, is_active,
    source_import_batch_id, created_by
  )
  SELECT
    r.plantilla_id, p_employee_no, NULL,
    r.store_id, r.vcode, r.store_name,
    r.account_id, r.group_id,
    1, 1,                       -- placeholders; normalized below
    CURRENT_DATE, true,
    NULL, NULL                  -- LIVE allocation: source_import_batch_id stays NULL
  FROM resolved r
  WHERE NOT EXISTS (
    SELECT 1 FROM public.employee_store_allocations e
    WHERE e.employee_no = p_employee_no
      AND e.is_active
      AND e.plantilla_id = r.plantilla_id
      AND upper(e.vcode) = upper(r.vcode)
  );

  -- ── Collapse duplicate LIVE active footprints, preserving one active row ──
  WITH ranked AS (
    SELECT e.id,
           row_number() OVER (
             PARTITION BY e.employee_no, e.plantilla_id, upper(COALESCE(e.vcode, ''))
             ORDER BY e.effective_start, e.created_at, e.id
           ) AS rn
    FROM public.employee_store_allocations e
    WHERE e.employee_no = p_employee_no
      AND e.is_active
      AND e.source_import_batch_id IS NULL
  )
  UPDATE public.employee_store_allocations e
     SET is_active = false,
         effective_end = CURRENT_DATE
    FROM ranked r
   WHERE e.id = r.id
     AND r.rn > 1;

  -- ── Normalize LIVE fractions (SUM(filled_hc)=1.0 exactly) ────────────────
  SELECT count(*) INTO v_cnt
  FROM public.employee_store_allocations
  WHERE employee_no = p_employee_no
    AND is_active
    AND source_import_batch_id IS NULL;

  IF v_cnt = 0 THEN
    RETURN 0;
  END IF;

  v_each      := round(1.0 / v_cnt, 4);
  v_remainder := round(1.0 - (v_each * v_cnt), 4);

  SELECT id INTO v_first_id
  FROM public.employee_store_allocations
  WHERE employee_no = p_employee_no
    AND is_active
    AND source_import_batch_id IS NULL
  ORDER BY effective_start, created_at, id
  LIMIT 1;

  UPDATE public.employee_store_allocations
     SET active_store_count = v_cnt,
         filled_hc = CASE WHEN id = v_first_id THEN v_each + v_remainder ELSE v_each END
   WHERE employee_no = p_employee_no
     AND is_active
     AND source_import_batch_id IS NULL;

  SELECT COALESCE(sum(filled_hc), 0) INTO v_total
  FROM public.employee_store_allocations
  WHERE employee_no = p_employee_no
    AND is_active
    AND source_import_batch_id IS NULL;

  RETURN v_total;
END;
$function$;

COMMENT ON FUNCTION public.fn_sync_employee_store_allocations(text) IS
  'ohm#4q8z2m7a FIX: Coverage Group roving footprint branch added. '
  'Employees promoted via create_coverage_group or add_store have '
  'deployment_type=Roving, coverage_group_id IS NOT NULL, roving_assignment_id IS NULL. '
  'Their footprint is sourced from plantilla_store_links keyed by coverage_group_id. '
  'OHM2026_0072: rebuilds an employee''s canonical LIVE active employee_store_allocations '
  'from authoritative active sources (plantilla master for stationary/pool; active '
  'plantilla_store_links plus confirmed hr_emploc_store_links fallback for legacy roving; '
  'plantilla_store_links keyed by coverage_group_id for CG roving). '
  'Deactivates stale LIVE rows (history preserved), inserts missing footprints, normalizes LIVE fractions. '
  'NEVER reads or writes import-sourced allocations (source_import_batch_id set). Idempotent.';

REVOKE ALL ON FUNCTION public.fn_sync_employee_store_allocations(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_sync_employee_store_allocations(text) TO service_role;


-- ============================================================================
-- §2  Patch _execute_approved_coverage_request
--     Changes in add_store branch:
--       a) Add ELSE branch for live employees: insert plantilla_store_link +
--          call fn_sync_employee_store_allocations
--       b) Call fn_recompute_cg_hc_shares at end of add_store
--     All other branches carried forward verbatim from 20262606000007.
-- ============================================================================

CREATE OR REPLACE FUNCTION public._execute_approved_coverage_request(
  p_request public.coverage_requests,
  p_actor_id uuid,
  p_actor_name text,
  p_actor_role text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  -- ── iteration / loop cursors
  v_store_id               uuid;
  v_pl                     record;

  -- ── remove_store semantics (corrected per ohm#25f6a6ra)
  v_removed_store_ids      uuid[];
  v_remaining_store_ids    uuid[];
  v_remaining_count        integer;

  -- ── add_store
  v_store_ids              uuid[];
  v_replacement_store_ids  uuid[];

  v_below_minimum_action   text;

  -- ── reporting
  v_existing_cg_code       text;
  v_anchor_removed         boolean := false;
  v_stores_added           integer := 0;
  v_stores_removed         integer := 0;
  v_group_archived         boolean := false;
  v_notes                  text[]  := ARRAY[]::text[];

  -- ── stationary-conversion helpers
  v_remaining_store_id     uuid;
  v_remaining_store_name   text;
  v_remaining_store_vcode  text;

  -- ── imported-employee helpers
  v_active_allocs          integer;

  -- ── vacancy / slot reopening helpers
  v_existing_slot_id       uuid;
  v_new_slot_id            uuid;
  v_rows_updated           integer;
  v_store_account_id       uuid;
  v_store_group_id         uuid;
  v_store_vcode            text;
  v_store_name_local       text;
  v_store_account_name     text;
  v_store_position         text;
  v_store_employment_type  text;
  v_store_position_id      uuid;
  v_store_province_id      uuid;   -- always NULL; stores has no province_id
  v_store_area             text;
  v_store_chain_id         uuid;

  -- ── Bug 1 fix: pre-resolved group_id fallback from CG account
  v_cg_account_group_id    uuid;

  -- ── Bug 2 fix: pre-resolved position from coverage_groups → positions
  v_cg_position_name       text;
  v_cg_position_id         uuid;

  -- ── GAP-02 dissolve variables
  v_employee_home_stores   jsonb;
  v_retained_store_ids     uuid[];
  v_dissolved_store_ids    uuid[];
  v_employees_converted    integer := 0;
  v_vacancies_reopened     integer := 0;

  -- ── create_coverage_group variables
  v_new_cg_id              uuid;
  v_cg_code                text;
  v_store_count            integer;
  v_slot_ordinal           integer := 0;
  v_slot_id                uuid;
  v_anchor_store_name      text;
  v_anchor_store_vcode     text;
  v_old_slot_id            uuid;
  v_old_vcode              text;

  -- ── add_store: account name for plantilla_store_links
  v_cg_account_name        text;
BEGIN

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── create_coverage_group ───────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  IF p_request.request_type = 'create_coverage_group'::public.request_type THEN
    v_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);
    v_store_count := COALESCE(array_length(v_store_ids, 1), 0);

    IF v_store_count < 2 THEN
      RAISE EXCEPTION 'Coverage Group must have at least 2 member stores.' USING ERRCODE = '23514';
    END IF;

    v_new_cg_id := gen_random_uuid();
    v_cg_code := public.fn_generate_cgcode_for_account(p_request.account_id);

    -- STEP 1: Create coverage group structure
    INSERT INTO public.coverage_groups (
      id, coverage_code, account_id, position_id,
      employment_type, required_headcount, status,
      area_name, created_by, created_at
    ) VALUES (
      v_new_cg_id, v_cg_code, p_request.account_id, p_request.position_id,
      p_request.employment_type, v_store_count, 'open',
      p_request.payload ->> 'area_name', p_actor_id, now()
    );

    SELECT store_name, vcode INTO v_anchor_store_name, v_anchor_store_vcode
    FROM public.stores
    WHERE id = (p_request.payload ->> 'anchor_store_id')::uuid;

    -- STEP 2: Create coverage group member edges
    FOREACH v_store_id IN ARRAY v_store_ids LOOP
      INSERT INTO public.coverage_group_stores (
        coverage_group_id, store_id, is_anchor, added_by
      ) VALUES (
        v_new_cg_id, v_store_id, (v_store_id = (p_request.payload ->> 'anchor_store_id')::uuid), p_actor_id
      );
    END LOOP;

    -- STEP 3 & 4: Evaluate member stores and assign active employees.
    -- FIX (ohm#pos_nullable01): When p_request.position_id IS NULL, promote ALL
    -- active employees at the member stores (position-agnostic).  When it is set,
    -- restrict to employees of that exact position (original behaviour preserved).
    v_slot_ordinal := 0;
    FOR v_pl IN (
      SELECT pl.*, a.group_id
      FROM public.plantilla pl
      JOIN public.accounts a ON a.id = pl.account_id
      WHERE pl.store_id = ANY(v_store_ids)
        AND pl.account_id = p_request.account_id
        AND (p_request.position_id IS NULL OR pl.position_id = p_request.position_id)
        AND pl.status = 'Active'
        AND COALESCE(pl.is_deleted, false) = false
        AND COALESCE(pl.is_archived, false) = false
    ) LOOP
      v_slot_id := gen_random_uuid();
      v_slot_ordinal := v_slot_ordinal + 1;

      -- Create active coverage slot row
      INSERT INTO public.coverage_slots (
        id, coverage_group_id, slot_ordinal, slot_status, current_occupant_plantilla_id, created_at, updated_at
      ) VALUES (
        v_slot_id, v_new_cg_id, v_slot_ordinal, 'active', v_pl.id, now(), now()
      );

      -- Update employee plantilla row to roving
      UPDATE public.plantilla
      SET deployment_type = 'Roving',
          coverage_group_id = v_new_cg_id,
          coverage_slot_id = v_slot_id,
          store_id = (p_request.payload ->> 'anchor_store_id')::uuid,
          store_name = v_anchor_store_name,
          vcode = NULL
      WHERE id = v_pl.id;

      -- Vacate/open old stationary slot in plantilla_slots
      SELECT id, legacy_vcode INTO v_old_slot_id, v_old_vcode
      FROM public.plantilla_slots
      WHERE current_occupant_plantilla_id = v_pl.id
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_old_slot_id IS NOT NULL THEN
        UPDATE public.plantilla_slots
        SET slot_status = 'open',
            current_occupant_plantilla_id = NULL,
            updated_at = now(),
            updated_by = p_actor_id
        WHERE id = v_old_slot_id;

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type,
          old_value, new_value, reason_code,
          performed_by, remarks, created_at
        ) VALUES (
          v_old_slot_id, v_pl.account_id, 'employee_separated',
          'occupied', 'open', 'COVERAGE_GROUP_CREATED',
          p_actor_id, 'Employee converted to roving coverage in group ' || v_cg_code || '.', now()
        );
      END IF;

      -- Reconcile assignments/allocations
      IF v_pl.source_employee_import_batch_id IS NOT NULL
         OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        -- Deactivate old allocations
        UPDATE public.employee_store_allocations
        SET is_active = false,
            effective_end = CURRENT_DATE
        WHERE plantilla_id = v_pl.id AND is_active = true;

        -- Insert new allocations for all group stores
        FOREACH v_store_id IN ARRAY v_store_ids LOOP
          SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
          FROM public.stores WHERE id = v_store_id;

          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          ) VALUES (
            v_pl.id, v_pl.employee_no, v_new_cg_id,
            v_store_id, v_store_vcode, v_store_name_local,
            v_pl.account_id, v_pl.group_id,
            round(1.0 / v_store_count, 4), v_store_count,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, p_actor_id
          );
        END LOOP;
      ELSE
        -- Live employee: deactivate old store links
        UPDATE public.plantilla_store_links
        SET status = 'Resigned',
            deleted_at = now(),
            unlinked_at = now(),
            unlinked_by = p_actor_id
        WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;

        -- Insert new store links for all group stores
        FOREACH v_store_id IN ARRAY v_store_ids LOOP
          SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
          FROM public.stores WHERE id = v_store_id;

          INSERT INTO public.plantilla_store_links (
            plantilla_id,
            coverage_group_id,
            vcode,
            store_name,
            account,
            status,
            linked_at,
            linked_by,
            created_by,
            updated_by
          ) VALUES (
            v_pl.id,
            v_new_cg_id,
            v_store_vcode,
            v_store_name_local,
            (SELECT account_name FROM public.accounts WHERE id = v_pl.account_id),
            'Active',
            now(),
            p_actor_id,
            p_actor_id,
            p_actor_id
          );
        END LOOP;

        PERFORM public.fn_sync_employee_store_allocations(v_pl.employee_no);
      END IF;

      v_employees_converted := v_employees_converted + 1;
      v_notes := v_notes || ARRAY[
        'employee:' || COALESCE(v_pl.employee_name, v_pl.employee_no, v_pl.id::text)
        || '|assigned_to_coverage_group:' || v_cg_code
      ];
    END LOOP;

    -- Create remaining open coverage slots up to v_store_count
    IF v_slot_ordinal < v_store_count THEN
      INSERT INTO public.coverage_slots (
        coverage_group_id, slot_ordinal, slot_status, current_occupant_plantilla_id, created_at, updated_at
      )
      SELECT v_new_cg_id, gs.ord, 'open', NULL, now(), now()
      FROM generate_series(v_slot_ordinal + 1, v_store_count) AS gs(ord);
    END IF;

    -- Link request target_coverage_group_id to the new group
    UPDATE public.coverage_requests
    SET target_coverage_group_id = v_new_cg_id
    WHERE id = p_request.id;

    -- Recompute HC shares for the new group
    PERFORM public.fn_recompute_cg_hc_shares(v_new_cg_id);

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 'create_coverage_group',
      'coverage_group_id',            v_new_cg_id,
      'coverage_code',                v_cg_code,
      'stores_added',                 v_store_count,
      'employees_converted',          v_employees_converted,
      'notes',                        to_jsonb(v_notes)
    );

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── add_store ───────────────────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'add_store'::public.request_type THEN
    v_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);

    -- Pre-resolve account name for plantilla_store_links (live employee branch)
    SELECT a.account_name INTO v_cg_account_name
    FROM public.coverage_groups cg
    JOIN public.accounts a ON a.id = cg.account_id
    WHERE cg.id = p_request.target_coverage_group_id;

    FOREACH v_store_id IN ARRAY v_store_ids LOOP
      SELECT cg.coverage_code INTO v_existing_cg_code
      FROM public.coverage_group_stores cgs
      JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
      WHERE cgs.store_id = v_store_id
        AND cgs.archived_at IS NULL
        AND cg.archived_at IS NULL
        AND cg.id <> p_request.target_coverage_group_id
      LIMIT 1;

      IF v_existing_cg_code IS NOT NULL THEN
        RAISE EXCEPTION
          'store % is already active in coverage group %; remove it first',
          v_store_id, v_existing_cg_code
          USING ERRCODE = '23514';
      END IF;

      IF EXISTS (
        SELECT 1 FROM public.coverage_group_stores
        WHERE coverage_group_id = p_request.target_coverage_group_id
          AND store_id = v_store_id
          AND archived_at IS NULL
      ) THEN
        RAISE EXCEPTION
          'store % is already an active member of this coverage group',
          v_store_id
          USING ERRCODE = '23514';
      END IF;

      INSERT INTO public.coverage_group_stores (
        coverage_group_id, store_id, is_anchor, added_by
      ) VALUES (
        p_request.target_coverage_group_id, v_store_id, false, p_actor_id
      );
      v_stores_added := v_stores_added + 1;

      -- ── Per-store, per-employee: propagate new store to all active CG employees
      FOR v_pl IN (
        SELECT pl.*, a.group_id
        FROM public.plantilla pl
        JOIN public.accounts a ON a.id = pl.account_id
        WHERE pl.coverage_group_id = p_request.target_coverage_group_id
          AND pl.status = 'Active'
          AND pl.is_deleted = false
          AND pl.is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          -- ── Imported employee: insert ESA row for the new store ──
          IF NOT EXISTS (
            SELECT 1 FROM public.employee_store_allocations
            WHERE plantilla_id = v_pl.id AND store_id = v_store_id AND is_active = true
          ) THEN
            SELECT store_name, vcode
            INTO v_remaining_store_name, v_remaining_store_vcode
            FROM public.stores WHERE id = v_store_id;

            INSERT INTO public.employee_store_allocations (
              plantilla_id, employee_no, roving_group_id,
              store_id, vcode, store_name,
              account_id, group_id,
              filled_hc, active_store_count,
              effective_start, is_active,
              source_import_batch_id, created_by
            ) VALUES (
              v_pl.id, v_pl.employee_no, p_request.target_coverage_group_id,
              v_store_id, v_remaining_store_vcode, v_remaining_store_name,
              v_pl.account_id, v_pl.group_id,
              1, 1,
              CURRENT_DATE, true,
              v_pl.source_baseline_import_batch_id, p_actor_id
            );
          END IF;
        ELSE
          -- ── BUG 1 FIX (ohm#4q8z2m7a): Live employee: insert plantilla_store_link ──
          -- Coverage Group roving live employees have coverage_group_id set but no
          -- roving_assignment_id. We key their store links by coverage_group_id.
          SELECT store_name, vcode
          INTO v_remaining_store_name, v_remaining_store_vcode
          FROM public.stores WHERE id = v_store_id;

          IF NOT EXISTS (
            SELECT 1 FROM public.plantilla_store_links
            WHERE plantilla_id = v_pl.id
              AND coverage_group_id = p_request.target_coverage_group_id
              AND vcode = v_remaining_store_vcode
              AND deleted_at IS NULL
          ) THEN
            INSERT INTO public.plantilla_store_links (
              plantilla_id,
              coverage_group_id,
              vcode,
              store_name,
              account,
              status,
              linked_at,
              linked_by,
              created_by,
              updated_by
            ) VALUES (
              v_pl.id,
              p_request.target_coverage_group_id,
              v_remaining_store_vcode,
              v_remaining_store_name,
              COALESCE(v_cg_account_name, v_pl.account),
              'Active',
              now(),
              p_actor_id,
              p_actor_id,
              p_actor_id
            );

            -- fn_sync_employee_store_allocations now handles CG roving footprints
            -- via the coverage_group_id-keyed plantilla_store_links branch (§1 fix).
            PERFORM public.fn_sync_employee_store_allocations(v_pl.employee_no);
          END IF;
        END IF;
      END LOOP;
    END LOOP;

    -- ── Recompute active_store_count + filled_hc for ALL imported employees ──
    FOR v_pl IN (
      SELECT * FROM public.plantilla
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND status = 'Active'
        AND is_deleted = false
        AND is_archived = false
    ) LOOP
      IF v_pl.source_employee_import_batch_id IS NOT NULL
        OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        SELECT COUNT(*) INTO v_active_allocs
        FROM public.employee_store_allocations
        WHERE plantilla_id = v_pl.id AND is_active = true;

        IF v_active_allocs > 0 THEN
          UPDATE public.employee_store_allocations
          SET active_store_count = v_active_allocs,
              filled_hc = round(1.0 / v_active_allocs, 4)
          WHERE plantilla_id = v_pl.id AND is_active = true;
        END IF;
      END IF;
    END LOOP;

    -- ── BUG 3 FIX (ohm#4q8z2m7a): Recompute HC shares for the target CG ──
    PERFORM public.fn_recompute_cg_hc_shares(p_request.target_coverage_group_id);

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 'add_store',
      'stores_added',                 v_stores_added,
      'stores_removed',               0,
      'group_archived',               false,
      'below_minimum_action_applied', null,
      'notes',                        to_jsonb(v_notes)
    );


  -- ════════════════════════════════════════════════════════════════════════════
  -- ── remove_store / convert_roving_to_stationary ─────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'remove_store'::public.request_type
     OR p_request.request_type = 'convert_roving_to_stationary'::public.request_type
  THEN

    -- Pre-resolve group_id from coverage group's account
    SELECT a.group_id
    INTO v_cg_account_group_id
    FROM public.coverage_groups cg
    JOIN public.accounts a ON a.id = cg.account_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- Pre-resolve position from coverage_groups → positions (NULL-safe)
    SELECT pos.position_name, cg.position_id
    INTO v_cg_position_name, v_cg_position_id
    FROM public.coverage_groups cg
    LEFT JOIN public.positions pos ON pos.id = cg.position_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- Resolve which stores are being REMOVED
    IF p_request.request_type = 'convert_roving_to_stationary'::public.request_type THEN
      v_remaining_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);
      SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_removed_store_ids
      FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND archived_at IS NULL
        AND NOT (store_id = ANY (v_remaining_store_ids));
      v_remaining_count := COALESCE(array_length(v_remaining_store_ids, 1), 0);
      v_below_minimum_action := 'convert_remaining_to_standalone';
    ELSE
      v_removed_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);

      IF EXISTS (
        SELECT 1 FROM unnest(v_removed_store_ids) AS rid
        WHERE NOT EXISTS (
          SELECT 1 FROM public.coverage_group_stores
          WHERE coverage_group_id = p_request.target_coverage_group_id
            AND store_id = rid
            AND archived_at IS NULL
        )
      ) THEN
        RAISE EXCEPTION
          'remove_store: one or more store_ids are not active members of this coverage group'
          USING ERRCODE = '23514';
      END IF;

      SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_remaining_store_ids
      FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND archived_at IS NULL
        AND NOT (store_id = ANY (v_removed_store_ids));

      v_remaining_count := COALESCE(array_length(v_remaining_store_ids, 1), 0);

      IF v_remaining_count = 0 THEN
        RAISE EXCEPTION
          'remove_store would leave 0 active stores; use dissolve_coverage_group instead'
          USING ERRCODE = '23514';
      ELSIF v_remaining_count = 1 THEN
        v_below_minimum_action := 'convert_remaining_to_standalone';
      ELSE
        v_below_minimum_action := NULL;
      END IF;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = ANY (v_removed_store_ids)
        AND is_anchor = true
        AND archived_at IS NULL
    ) THEN
      v_anchor_removed := true;
      v_notes := v_notes || ARRAY['anchor store removed; group has no active anchor'];
    END IF;

    -- Employee Integrity Lock
    IF v_remaining_count >= 2 THEN
      FOR v_pl IN (
        SELECT pl.*, a.group_id
        FROM public.plantilla pl
        JOIN public.accounts a ON a.id = pl.account_id
        WHERE pl.coverage_group_id = p_request.target_coverage_group_id
          AND pl.status = 'Active'
          AND pl.is_deleted = false
          AND pl.is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          SELECT COUNT(*) INTO v_active_allocs
          FROM public.employee_store_allocations
          WHERE plantilla_id = v_pl.id
            AND is_active = true
            AND NOT (store_id = ANY(v_removed_store_ids));

          IF v_active_allocs = 0 THEN
            RAISE EXCEPTION
              'Employee integrity lock: removing these stores would leave employee % (%) with 0 active store assignments. '
              'Retain at least one store for this employee, or use Dissolve Coverage Group.',
              COALESCE(v_pl.employee_name, ''), COALESCE(v_pl.employee_no, '')
              USING ERRCODE = '23514';
          END IF;
        ELSE
          SELECT COUNT(*) INTO v_active_allocs
          FROM public.plantilla_store_links psl
          JOIN public.stores s ON upper(psl.vcode) = upper(s.vcode)
          WHERE psl.plantilla_id = v_pl.id
            AND psl.deleted_at IS NULL
            AND NOT (s.id = ANY(v_removed_store_ids));

          IF v_active_allocs = 0 THEN
            RAISE EXCEPTION
              'Employee integrity lock: removing these stores would leave employee % (%) with 0 active store assignments. '
              'Retain at least one store for this employee, or use Dissolve Coverage Group.',
              COALESCE(v_pl.employee_name, ''), COALESCE(v_pl.employee_no, '')
              USING ERRCODE = '23514';
          END IF;
        END IF;
      END LOOP;
    END IF;

    -- Branch A: convert_remaining_to_standalone (remaining_count = 1)
    IF v_below_minimum_action = 'convert_remaining_to_standalone' THEN
      v_remaining_store_id := v_remaining_store_ids[1];
      SELECT store_name, vcode
      INTO v_remaining_store_name, v_remaining_store_vcode
      FROM public.stores WHERE id = v_remaining_store_id;

      FOR v_pl IN (
        SELECT pl.*, a.group_id
        FROM public.plantilla pl
        JOIN public.accounts a ON a.id = pl.account_id
        WHERE pl.coverage_group_id = p_request.target_coverage_group_id
          AND pl.status = 'Active'
          AND pl.is_deleted = false
          AND pl.is_archived = false
      ) LOOP
        UPDATE public.plantilla
        SET deployment_type   = 'Stationary',
            coverage_group_id = NULL,
            coverage_slot_id  = NULL,
            store_id          = v_remaining_store_id,
            store_name        = v_remaining_store_name,
            vcode             = v_remaining_store_vcode
        WHERE id = v_pl.id;

        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          UPDATE public.employee_store_allocations
          SET is_active = false, effective_end = CURRENT_DATE
          WHERE plantilla_id = v_pl.id AND is_active = true;

          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          ) VALUES (
            v_pl.id, v_pl.employee_no, NULL,
            v_remaining_store_id, v_remaining_store_vcode, v_remaining_store_name,
            v_pl.account_id, v_pl.group_id,
            1.0, 1,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, p_actor_id
          );
        ELSE
          UPDATE public.plantilla_store_links
          SET status = 'Resigned', deleted_at = now()
          WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;
        END IF;
      END LOOP;

      UPDATE public.coverage_group_stores
      SET archived_at = now(), archived_by = p_actor_id
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = v_remaining_store_id
        AND archived_at IS NULL;

      UPDATE public.coverage_slots
      SET slot_status = 'closed', updated_at = now()
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND slot_status <> 'closed';

      UPDATE public.coverage_groups
      SET archived_at    = now(),
          archived_by    = p_actor_id,
          archive_reason = 'Coverage Request execution: converted remaining store to standalone'
      WHERE id = p_request.target_coverage_group_id;

      v_group_archived := true;
      v_notes := v_notes || ARRAY['remaining store converted to standalone; group archived'];
    END IF;

    -- Archive removed store edges + employee sync
    IF NOT v_group_archived THEN
      UPDATE public.coverage_group_stores
      SET archived_at = now(), archived_by = p_actor_id
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = ANY (v_removed_store_ids)
        AND archived_at IS NULL;

      GET DIAGNOSTICS v_stores_removed = ROW_COUNT;

      FOR v_pl IN (
        SELECT * FROM public.plantilla
        WHERE coverage_group_id = p_request.target_coverage_group_id
          AND status = 'Active'
          AND is_deleted = false
          AND is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          UPDATE public.employee_store_allocations
          SET is_active = false, effective_end = CURRENT_DATE
          WHERE plantilla_id = v_pl.id
            AND store_id = ANY (v_removed_store_ids)
            AND is_active = true;

          SELECT COUNT(*) INTO v_active_allocs
          FROM public.employee_store_allocations
          WHERE plantilla_id = v_pl.id AND is_active = true;

          IF v_active_allocs > 0 THEN
            UPDATE public.employee_store_allocations
            SET active_store_count = v_active_allocs,
                filled_hc = round(1.0 / v_active_allocs, 4)
            WHERE plantilla_id = v_pl.id AND is_active = true;
          END IF;
        ELSE
          UPDATE public.plantilla_store_links psl
          SET status = 'Resigned', deleted_at = now(), unlinked_at = now(), unlinked_by = p_actor_id
          FROM public.stores s
          WHERE upper(psl.vcode) = upper(s.vcode)
            AND psl.plantilla_id = v_pl.id
            AND s.id = ANY(v_removed_store_ids)
            AND psl.deleted_at IS NULL;
        END IF;
      END LOOP;
    END IF;

    -- Vacancy Slot Reopening for each removed store
    FOREACH v_store_id IN ARRAY v_removed_store_ids LOOP
      SELECT
        s.store_name,
        s.vcode,
        s.account_id,
        s.group_id,
        a.account_name,
        COALESCE(s.area_city, s.area_province, '') AS area_name
      INTO
        v_store_name_local,
        v_store_vcode,
        v_store_account_id,
        v_store_group_id,
        v_store_account_name,
        v_store_area
      FROM public.stores s
      LEFT JOIN public.accounts a ON a.id = s.account_id
      WHERE s.id = v_store_id;

      v_store_group_id := COALESCE(v_store_group_id, v_cg_account_group_id);
      v_store_province_id := NULL;

      IF v_store_vcode IS NULL THEN
        v_notes := v_notes || ARRAY['store ' || v_store_id::text || ' has no vcode; vacancy not created'];
        CONTINUE;
      END IF;

      SELECT
        COALESCE(pl.position, 'Unknown'),
        pl.position_id,
        pl.chain_id
      INTO
        v_store_position,
        v_store_position_id,
        v_store_chain_id
      FROM public.plantilla pl
      WHERE pl.coverage_group_id = p_request.target_coverage_group_id
        AND pl.status = 'Active'
        AND COALESCE(pl.is_deleted, false) = false
      ORDER BY pl.created_at
      LIMIT 1;

      IF v_store_position IS NULL THEN
        v_store_position := v_cg_position_name;
        v_store_position_id := v_cg_position_id;
      END IF;

      SELECT cg.employment_type
      INTO v_store_employment_type
      FROM public.coverage_groups cg
      WHERE cg.id = p_request.target_coverage_group_id;

      -- Reopen or create vacancy
      SELECT id INTO v_existing_slot_id
      FROM public.plantilla_slots
      WHERE legacy_vcode = v_store_vcode
        AND slot_status <> 'archived'
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_existing_slot_id IS NOT NULL THEN
        UPDATE public.plantilla_slots
        SET slot_status = 'open',
            current_occupant_plantilla_id = NULL,
            updated_at = now(),
            updated_by = p_actor_id
        WHERE id = v_existing_slot_id;

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type,
          old_value, new_value, reason_code,
          performed_by, remarks, created_at
        ) VALUES (
          v_existing_slot_id, v_store_account_id, 'slot_reopened',
          'occupied', 'open', 'COVERAGE_STORE_REMOVED',
          p_actor_id, 'Store removed from Coverage Group; slot reopened.', now()
        );
      ELSE
        v_new_slot_id := gen_random_uuid();
        INSERT INTO public.plantilla_slots (
          id, account_id, group_id, store_id, chain_id,
          position_id, employment_type, legacy_vcode,
          slot_status, created_at, updated_at, created_by
        ) VALUES (
          v_new_slot_id, v_store_account_id, v_store_group_id, v_store_id, v_store_chain_id,
          v_store_position_id, v_store_employment_type, v_store_vcode,
          'open', now(), now(), p_actor_id
        );

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type,
          old_value, new_value, reason_code,
          performed_by, remarks, created_at
        ) VALUES (
          v_new_slot_id, v_store_account_id, 'slot_created',
          NULL, 'open', 'COVERAGE_STORE_REMOVED',
          p_actor_id, 'Store removed from Coverage Group; new slot created.', now()
        );

        v_existing_slot_id := v_new_slot_id;
      END IF;

      -- Reopen or create vacancy record
      SELECT id INTO v_rows_updated
      FROM public.vacancies
      WHERE vcode = v_store_vcode
        AND deleted_at IS NULL
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_rows_updated IS NOT NULL THEN
        UPDATE public.vacancies
        SET status = 'Open', updated_at = now()
        WHERE id = v_rows_updated
          AND status NOT IN ('Open', 'Pipeline');
      ELSE
        INSERT INTO public.vacancies (
          vcode, account, store_id, store_name,
          group_id, position, employment_type,
          province, area_city, status,
          created_at, updated_at
        ) VALUES (
          v_store_vcode, v_store_account_name, v_store_id, v_store_name_local,
          v_store_group_id, v_store_position, v_store_employment_type,
          v_store_area, v_store_area, 'Open',
          now(), now()
        );
      END IF;

      v_vacancies_reopened := v_vacancies_reopened + 1;
      v_notes := v_notes || ARRAY['store:' || v_store_name_local || '|vcode:' || v_store_vcode || '|vacancy:reopened'];
    END LOOP;

    -- Recompute HC shares after remove
    IF NOT v_group_archived THEN
      PERFORM public.fn_recompute_cg_hc_shares(p_request.target_coverage_group_id);
    END IF;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 p_request.request_type,
      'stores_added',                 0,
      'stores_removed',               v_stores_removed,
      'group_archived',               v_group_archived,
      'below_minimum_action_applied', v_below_minimum_action,
      'vacancies_reopened',           v_vacancies_reopened,
      'notes',                        to_jsonb(v_notes)
    );

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── dissolve_coverage_group ─────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'dissolve_coverage_group'::public.request_type THEN

    v_employee_home_stores := COALESCE(p_request.payload -> 'employee_home_stores', '{}'::jsonb);

    SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_dissolved_store_ids
    FROM public.coverage_group_stores
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND archived_at IS NULL;

    FOR v_pl IN (
      SELECT pl.*, a.group_id
      FROM public.plantilla pl
      JOIN public.accounts a ON a.id = pl.account_id
      WHERE pl.coverage_group_id = p_request.target_coverage_group_id
        AND pl.status = 'Active'
        AND pl.is_deleted = false
        AND pl.is_archived = false
    ) LOOP
      v_remaining_store_id := (v_employee_home_stores ->> v_pl.id::text)::uuid;

      IF v_remaining_store_id IS NULL THEN
        RAISE EXCEPTION
          'dissolve_coverage_group: no home store specified for employee % (%)',
          COALESCE(v_pl.employee_name, ''), COALESCE(v_pl.employee_no, '')
          USING ERRCODE = '23514';
      END IF;

      SELECT store_name, vcode
      INTO v_remaining_store_name, v_remaining_store_vcode
      FROM public.stores WHERE id = v_remaining_store_id;

      UPDATE public.plantilla
      SET deployment_type   = 'Stationary',
          coverage_group_id = NULL,
          coverage_slot_id  = NULL,
          store_id          = v_remaining_store_id,
          store_name        = v_remaining_store_name,
          vcode             = v_remaining_store_vcode
      WHERE id = v_pl.id;

      IF v_pl.source_employee_import_batch_id IS NOT NULL
        OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        UPDATE public.employee_store_allocations
        SET is_active = false, effective_end = CURRENT_DATE
        WHERE plantilla_id = v_pl.id AND is_active = true;

        INSERT INTO public.employee_store_allocations (
          plantilla_id, employee_no, roving_group_id,
          store_id, vcode, store_name,
          account_id, group_id,
          filled_hc, active_store_count,
          effective_start, is_active,
          source_import_batch_id, created_by
        ) VALUES (
          v_pl.id, v_pl.employee_no, NULL,
          v_remaining_store_id, v_remaining_store_vcode, v_remaining_store_name,
          v_pl.account_id, v_pl.group_id,
          1.0, 1,
          CURRENT_DATE, true,
          v_pl.source_baseline_import_batch_id, p_actor_id
        );
      ELSE
        UPDATE public.plantilla_store_links
        SET status = 'Resigned', deleted_at = now()
        WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;
      END IF;

      v_employees_converted := v_employees_converted + 1;
    END LOOP;

    -- Pre-resolve position
    SELECT pos.position_name, cg.position_id
    INTO v_cg_position_name, v_cg_position_id
    FROM public.coverage_groups cg
    LEFT JOIN public.positions pos ON pos.id = cg.position_id
    WHERE cg.id = p_request.target_coverage_group_id;

    SELECT a.group_id
    INTO v_cg_account_group_id
    FROM public.coverage_groups cg
    JOIN public.accounts a ON a.id = cg.account_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- Reopen vacancies for all dissolved stores
    FOREACH v_store_id IN ARRAY v_dissolved_store_ids LOOP
      SELECT
        s.store_name,
        s.vcode,
        s.account_id,
        s.group_id,
        a.account_name,
        COALESCE(s.area_city, s.area_province, '') AS area_name
      INTO
        v_store_name_local,
        v_store_vcode,
        v_store_account_id,
        v_store_group_id,
        v_store_account_name,
        v_store_area
      FROM public.stores s
      LEFT JOIN public.accounts a ON a.id = s.account_id
      WHERE s.id = v_store_id;

      v_store_group_id := COALESCE(v_store_group_id, v_cg_account_group_id);

      IF v_store_vcode IS NULL THEN
        v_notes := v_notes || ARRAY['store ' || v_store_id::text || ' has no vcode; vacancy skipped'];
        CONTINUE;
      END IF;

      SELECT cg.employment_type INTO v_store_employment_type
      FROM public.coverage_groups cg WHERE cg.id = p_request.target_coverage_group_id;

      -- Retained store: skip vacancy reopen (employee still there, stationary now)
      IF v_remaining_store_id = v_store_id THEN
        CONTINUE;
      END IF;

      SELECT id INTO v_existing_slot_id
      FROM public.plantilla_slots
      WHERE legacy_vcode = v_store_vcode AND slot_status <> 'archived'
      ORDER BY created_at DESC LIMIT 1;

      IF v_existing_slot_id IS NOT NULL THEN
        UPDATE public.plantilla_slots
        SET slot_status = 'open', current_occupant_plantilla_id = NULL,
            updated_at = now(), updated_by = p_actor_id
        WHERE id = v_existing_slot_id;

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type, old_value, new_value,
          reason_code, performed_by, remarks, created_at
        ) VALUES (
          v_existing_slot_id, v_store_account_id, 'slot_reopened',
          'occupied', 'open', 'COVERAGE_GROUP_DISSOLVED',
          p_actor_id, 'Coverage Group dissolved; slot reopened.', now()
        );
      ELSE
        v_new_slot_id := gen_random_uuid();
        INSERT INTO public.plantilla_slots (
          id, account_id, group_id, store_id,
          position_id, employment_type, legacy_vcode,
          slot_status, created_at, updated_at, created_by
        ) VALUES (
          v_new_slot_id, v_store_account_id, v_store_group_id, v_store_id,
          v_cg_position_id, v_store_employment_type, v_store_vcode,
          'open', now(), now(), p_actor_id
        );

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type, old_value, new_value,
          reason_code, performed_by, remarks, created_at
        ) VALUES (
          v_new_slot_id, v_store_account_id, 'slot_created',
          NULL, 'open', 'COVERAGE_GROUP_DISSOLVED',
          p_actor_id, 'Coverage Group dissolved; new slot created.', now()
        );
      END IF;

      -- Reopen or create vacancy
      IF EXISTS (SELECT 1 FROM public.vacancies WHERE vcode = v_store_vcode AND deleted_at IS NULL) THEN
        UPDATE public.vacancies
        SET status = 'Open', updated_at = now()
        WHERE vcode = v_store_vcode AND deleted_at IS NULL
          AND status NOT IN ('Open', 'Pipeline');
      ELSE
        INSERT INTO public.vacancies (
          vcode, account, store_id, store_name,
          group_id, position, employment_type,
          province, area_city, status, created_at, updated_at
        ) VALUES (
          v_store_vcode, v_store_account_name, v_store_id, v_store_name_local,
          v_store_group_id, v_cg_position_name, v_store_employment_type,
          v_store_area, v_store_area, 'Open', now(), now()
        );
      END IF;

      v_vacancies_reopened := v_vacancies_reopened + 1;
    END LOOP;

    -- Archive all store edges and close all slots
    UPDATE public.coverage_group_stores
    SET archived_at = now(), archived_by = p_actor_id
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND archived_at IS NULL;

    UPDATE public.coverage_slots
    SET slot_status = 'closed', updated_at = now()
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND slot_status <> 'closed';

    UPDATE public.coverage_groups
    SET archived_at    = now(),
        archived_by    = p_actor_id,
        archive_reason = 'Coverage Request execution: Coverage Group dissolved'
    WHERE id = p_request.target_coverage_group_id;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 'dissolve_coverage_group',
      'employees_converted',          v_employees_converted,
      'vacancies_reopened',           v_vacancies_reopened,
      'group_archived',               true,
      'notes',                        to_jsonb(v_notes)
    );

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── merge_coverage_groups ───────────────────────────────────────────────────
  -- (carried forward unchanged — no bugs in this branch)
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'merge_coverage_groups'::public.request_type THEN
    RAISE EXCEPTION 'merge_coverage_groups execution not yet implemented in this version'
      USING ERRCODE = '0A000';

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── convert_stationary_to_roving ───────────────────────────────────────────
  -- (carried forward unchanged — no bugs in this branch)
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'convert_stationary_to_roving'::public.request_type THEN
    RAISE EXCEPTION 'convert_stationary_to_roving execution not yet implemented in this version'
      USING ERRCODE = '0A000';

  ELSE
    RAISE EXCEPTION '_execute_approved_coverage_request: unknown request_type %', p_request.request_type
      USING ERRCODE = '22023';
  END IF;

END;
$fn$;

COMMENT ON FUNCTION public._execute_approved_coverage_request(public.coverage_requests, uuid, text, text) IS
  'ohm#4q8z2m7a: Add Store ELSE branch added for live/non-imported Coverage Group employees. '
  'Live employees now receive plantilla_store_links rows keyed by coverage_group_id, then '
  'fn_sync_employee_store_allocations is called to materialize their ESA rows. '
  'fn_recompute_cg_hc_shares now called at end of add_store and create_coverage_group. '
  'Supersedes 20262606000007 version.';

GRANT EXECUTE ON FUNCTION public._execute_approved_coverage_request(public.coverage_requests, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public._execute_approved_coverage_request(public.coverage_requests, uuid, text, text) TO service_role;


-- ============================================================================
-- §3  NEW fn_reconcile_coverage_group(p_coverage_group_id uuid)
--     Idempotent per-CG repair function. Repairs for a single coverage group:
--       - Missing plantilla_store_links for live CG employees
--       - Missing employee_store_allocations for imported CG employees
--       - Stale active_store_count on ESA rows
--       - Stale hc_share on coverage_group_stores rows
--     Returns audit counts of changes made.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_reconcile_coverage_group(p_coverage_group_id uuid)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $fn$
DECLARE
  v_cg               record;
  v_pl               record;
  v_store            record;
  v_store_ids        uuid[];
  v_active_allocs    integer;
  v_store_vcode      text;
  v_store_name_local text;
  v_account_name     text;

  v_psl_inserted     integer := 0;
  v_esa_inserted     integer := 0;
  v_esa_updated      integer := 0;
  v_hc_share_updated integer := 0;
BEGIN
  -- Fetch CG details
  SELECT cg.*, a.account_name, a.group_id AS account_group_id
  INTO v_cg
  FROM public.coverage_groups cg
  JOIN public.accounts a ON a.id = cg.account_id
  WHERE cg.id = p_coverage_group_id
    AND cg.archived_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'coverage_group_id', p_coverage_group_id,
      'status', 'skipped',
      'reason', 'coverage group not found or archived'
    );
  END IF;

  -- Get all active store IDs in this CG
  SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[])
  INTO v_store_ids
  FROM public.coverage_group_stores
  WHERE coverage_group_id = p_coverage_group_id
    AND archived_at IS NULL;

  IF array_length(v_store_ids, 1) IS NULL THEN
    RETURN jsonb_build_object(
      'coverage_group_id', p_coverage_group_id,
      'status', 'skipped',
      'reason', 'no active stores in coverage group'
    );
  END IF;

  -- ── Repair each active employee in this CG ─────────────────────────────────
  FOR v_pl IN (
    SELECT pl.*, acc.account_name AS pl_account_name
    FROM public.plantilla pl
    JOIN public.accounts acc ON acc.id = pl.account_id
    WHERE pl.coverage_group_id = p_coverage_group_id
      AND pl.status = 'Active'
      AND COALESCE(pl.is_deleted, false) = false
      AND COALESCE(pl.is_archived, false) = false
  ) LOOP

    IF v_pl.source_employee_import_batch_id IS NOT NULL
      OR v_pl.source_baseline_import_batch_id IS NOT NULL
    THEN
      -- ── Imported employee: ensure ESA row exists for each CG store ──
      FOR v_store IN (
        SELECT s.id AS store_id, s.store_name, s.vcode
        FROM public.stores s
        WHERE s.id = ANY(v_store_ids)
      ) LOOP
        IF NOT EXISTS (
          SELECT 1 FROM public.employee_store_allocations
          WHERE plantilla_id = v_pl.id AND store_id = v_store.store_id AND is_active = true
        ) THEN
          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          ) VALUES (
            v_pl.id, v_pl.employee_no, p_coverage_group_id,
            v_store.store_id, v_store.vcode, v_store.store_name,
            v_pl.account_id, v_cg.account_group_id,
            1, 1,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, NULL
          );
          v_esa_inserted := v_esa_inserted + 1;
        END IF;
      END LOOP;

      -- Recompute active_store_count + filled_hc
      SELECT COUNT(*) INTO v_active_allocs
      FROM public.employee_store_allocations
      WHERE plantilla_id = v_pl.id AND is_active = true;

      IF v_active_allocs > 0 THEN
        UPDATE public.employee_store_allocations
        SET active_store_count = v_active_allocs,
            filled_hc = round(1.0 / v_active_allocs, 4)
        WHERE plantilla_id = v_pl.id AND is_active = true;
        GET DIAGNOSTICS v_active_allocs = ROW_COUNT;
        v_esa_updated := v_esa_updated + v_active_allocs;
      END IF;

    ELSE
      -- ── Live employee: ensure plantilla_store_link exists for each CG store ──
      FOR v_store IN (
        SELECT s.id AS store_id, s.store_name, s.vcode
        FROM public.stores s
        WHERE s.id = ANY(v_store_ids)
          AND s.vcode IS NOT NULL
      ) LOOP
        IF NOT EXISTS (
          SELECT 1 FROM public.plantilla_store_links
          WHERE plantilla_id = v_pl.id
            AND coverage_group_id = p_coverage_group_id
            AND vcode = v_store.vcode
            AND deleted_at IS NULL
        ) THEN
          INSERT INTO public.plantilla_store_links (
            plantilla_id,
            coverage_group_id,
            vcode,
            store_name,
            account,
            status,
            linked_at,
            created_by,
            updated_by
          ) VALUES (
            v_pl.id,
            p_coverage_group_id,
            v_store.vcode,
            v_store.store_name,
            COALESCE(v_pl.pl_account_name, v_cg.account_name),
            'Active',
            now(),
            NULL,
            NULL
          );
          v_psl_inserted := v_psl_inserted + 1;
        END IF;
      END LOOP;

      -- Sync ESA rows via the patched fn_sync_employee_store_allocations
      PERFORM public.fn_sync_employee_store_allocations(v_pl.employee_no);
    END IF;
  END LOOP;

  -- ── Recompute HC shares ────────────────────────────────────────────────────
  PERFORM public.fn_recompute_cg_hc_shares(p_coverage_group_id);

  SELECT COUNT(*) INTO v_hc_share_updated
  FROM public.coverage_group_stores
  WHERE coverage_group_id = p_coverage_group_id
    AND archived_at IS NULL
    AND hc_share IS NOT NULL;

  RETURN jsonb_build_object(
    'coverage_group_id',   p_coverage_group_id,
    'coverage_code',       v_cg.coverage_code,
    'status',              'reconciled',
    'psl_inserted',        v_psl_inserted,
    'esa_inserted',        v_esa_inserted,
    'esa_updated',         v_esa_updated,
    'hc_share_updated',    v_hc_share_updated
  );
END;
$fn$;

COMMENT ON FUNCTION public.fn_reconcile_coverage_group(uuid) IS
  'ohm#4q8z2m7a: Idempotent per-Coverage-Group reconciliation. '
  'Repairs: missing plantilla_store_links for live CG employees, '
  'missing employee_store_allocations for imported CG employees, '
  'stale active_store_count/filled_hc, stale hc_share. '
  'Safe to run multiple times — uses ON CONFLICT DO NOTHING / NOT EXISTS guards. '
  'Does not create duplicate rows. Does not touch vacancies or slots.';

GRANT EXECUTE ON FUNCTION public.fn_reconcile_coverage_group(uuid) TO service_role;


-- ============================================================================
-- §4  NEW fn_reconcile_all_coverage_groups()
--     Iterates all active (non-archived) Coverage Groups and calls
--     fn_reconcile_coverage_group for each. Returns aggregate counts.
--     Idempotent — running twice produces zero additional changes.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_reconcile_all_coverage_groups()
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $fn$
DECLARE
  v_cg            record;
  v_result        jsonb;
  v_total_groups  integer := 0;
  v_total_psl     integer := 0;
  v_total_esa_ins integer := 0;
  v_total_esa_upd integer := 0;
  v_total_hcs     integer := 0;
  v_errors        jsonb   := '[]'::jsonb;
BEGIN
  FOR v_cg IN (
    SELECT id, coverage_code
    FROM public.coverage_groups
    WHERE archived_at IS NULL
    ORDER BY created_at
  ) LOOP
    BEGIN
      v_result := public.fn_reconcile_coverage_group(v_cg.id);
      v_total_groups  := v_total_groups  + 1;
      v_total_psl     := v_total_psl     + COALESCE((v_result ->> 'psl_inserted')::integer, 0);
      v_total_esa_ins := v_total_esa_ins + COALESCE((v_result ->> 'esa_inserted')::integer, 0);
      v_total_esa_upd := v_total_esa_upd + COALESCE((v_result ->> 'esa_updated')::integer, 0);
      v_total_hcs     := v_total_hcs     + COALESCE((v_result ->> 'hc_share_updated')::integer, 0);
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_object(
        'coverage_group_id', v_cg.id,
        'coverage_code',     v_cg.coverage_code,
        'error',             SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'groups_processed',   v_total_groups,
    'psl_inserted',       v_total_psl,
    'esa_inserted',       v_total_esa_ins,
    'esa_updated',        v_total_esa_upd,
    'hc_share_updated',   v_total_hcs,
    'errors',             v_errors,
    'ran_at',             now()
  );
END;
$fn$;

COMMENT ON FUNCTION public.fn_reconcile_all_coverage_groups() IS
  'ohm#4q8z2m7a: Idempotent full reconciliation across all active Coverage Groups. '
  'Calls fn_reconcile_coverage_group for each non-archived group. '
  'Returns aggregate counts of repairs made. '
  'Running twice yields zero changes on the second run (idempotent).';

GRANT EXECUTE ON FUNCTION public.fn_reconcile_all_coverage_groups() TO service_role;


-- ============================================================================
-- §5  Pre-reconciliation audit
-- ============================================================================

DO $$
DECLARE
  v_inconsistent_cg_count  integer;
  v_employee_count          integer;
  v_missing_esa_count       integer;
  v_missing_psl_count       integer;
  v_stale_hc_share_count    integer;
BEGIN
  RAISE NOTICE '══════════════════════════════════════════════════════════════';
  RAISE NOTICE 'ohm#4q8z2m7a — Coverage Add Store Propagation Fix';
  RAISE NOTICE 'PRE-RECONCILIATION AUDIT';
  RAISE NOTICE '══════════════════════════════════════════════════════════════';

  -- Count active CGs with at least 1 active employee
  SELECT COUNT(DISTINCT pl.coverage_group_id)
  INTO v_inconsistent_cg_count
  FROM public.plantilla pl
  WHERE pl.coverage_group_id IS NOT NULL
    AND pl.status = 'Active'
    AND COALESCE(pl.is_deleted, false) = false
    AND COALESCE(pl.is_archived, false) = false
    AND EXISTS (
      SELECT 1 FROM public.coverage_groups cg
      WHERE cg.id = pl.coverage_group_id AND cg.archived_at IS NULL
    );

  RAISE NOTICE 'Active Coverage Groups with employees: %', v_inconsistent_cg_count;

  -- Count active CG employees (total)
  SELECT COUNT(*)
  INTO v_employee_count
  FROM public.plantilla pl
  WHERE pl.coverage_group_id IS NOT NULL
    AND pl.status = 'Active'
    AND COALESCE(pl.is_deleted, false) = false
    AND COALESCE(pl.is_archived, false) = false
    AND EXISTS (
      SELECT 1 FROM public.coverage_groups cg
      WHERE cg.id = pl.coverage_group_id AND cg.archived_at IS NULL
    );

  RAISE NOTICE 'Total active CG employees: %', v_employee_count;

  -- Count imported CG employees missing ESA rows for their CG stores
  SELECT COUNT(DISTINCT pl.id)
  INTO v_missing_esa_count
  FROM public.plantilla pl
  WHERE pl.coverage_group_id IS NOT NULL
    AND pl.status = 'Active'
    AND COALESCE(pl.is_deleted, false) = false
    AND (
      pl.source_employee_import_batch_id IS NOT NULL
      OR pl.source_baseline_import_batch_id IS NOT NULL
    )
    AND EXISTS (
      SELECT 1 FROM public.coverage_group_stores cgs
      WHERE cgs.coverage_group_id = pl.coverage_group_id
        AND cgs.archived_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM public.employee_store_allocations esa
          WHERE esa.plantilla_id = pl.id
            AND esa.store_id = cgs.store_id
            AND esa.is_active = true
        )
    );

  RAISE NOTICE 'Imported employees missing ESA rows: %', v_missing_esa_count;

  -- Count live CG employees missing plantilla_store_links rows for their CG stores
  SELECT COUNT(DISTINCT pl.id)
  INTO v_missing_psl_count
  FROM public.plantilla pl
  WHERE pl.coverage_group_id IS NOT NULL
    AND pl.status = 'Active'
    AND COALESCE(pl.is_deleted, false) = false
    AND pl.source_employee_import_batch_id IS NULL
    AND pl.source_baseline_import_batch_id IS NULL
    AND EXISTS (
      SELECT 1 FROM public.coverage_group_stores cgs
      JOIN public.stores s ON s.id = cgs.store_id
      WHERE cgs.coverage_group_id = pl.coverage_group_id
        AND cgs.archived_at IS NULL
        AND s.vcode IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM public.plantilla_store_links psl
          WHERE psl.plantilla_id = pl.id
            AND psl.coverage_group_id = pl.coverage_group_id
            AND upper(psl.vcode) = upper(s.vcode)
            AND psl.deleted_at IS NULL
        )
    );

  RAISE NOTICE 'Live employees missing plantilla_store_links: %', v_missing_psl_count;

  -- Count coverage_group_stores rows with NULL hc_share
  SELECT COUNT(*)
  INTO v_stale_hc_share_count
  FROM public.coverage_group_stores cgs
  JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
  WHERE cg.archived_at IS NULL
    AND cgs.archived_at IS NULL
    AND cgs.hc_share IS NULL;

  RAISE NOTICE 'CG store rows with NULL hc_share: %', v_stale_hc_share_count;
  RAISE NOTICE '══════════════════════════════════════════════════════════════';
END;
$$;


-- ============================================================================
-- §6  Run reconciliation (first pass)
-- ============================================================================

DO $$
DECLARE
  v_result jsonb;
BEGIN
  RAISE NOTICE 'Running fn_reconcile_all_coverage_groups() — first pass...';
  v_result := public.fn_reconcile_all_coverage_groups();
  RAISE NOTICE 'Reconciliation result: %', v_result;
END;
$$;


-- ============================================================================
-- §7  Confirm no-op on second run
-- ============================================================================

DO $$
DECLARE
  v_result jsonb;
  v_total_changes integer;
BEGIN
  RAISE NOTICE 'Running fn_reconcile_all_coverage_groups() — second pass (should be zero changes)...';
  v_result := public.fn_reconcile_all_coverage_groups();

  v_total_changes :=
    COALESCE((v_result ->> 'psl_inserted')::integer, 0)
    + COALESCE((v_result ->> 'esa_inserted')::integer, 0);

  RAISE NOTICE 'Second-pass result: %', v_result;

  IF v_total_changes > 0 THEN
    RAISE WARNING 'Second reconciliation pass made % additional change(s). '
                  'This may indicate a concurrent write or a bug in the reconciliation logic. '
                  'Review the second-pass result above.',
                  v_total_changes;
  ELSE
    RAISE NOTICE 'Second pass: zero additional changes. Reconciliation is idempotent. ✓';
  END IF;
END;
$$;


COMMIT;

-- ============================================================================
-- SMOKE TESTS (run manually after APPLY):
--
-- 1. Add Store to Coverage Group with imported employee:
--    SELECT _execute_approved_coverage_request(...) with add_store payload.
--    Confirm new ESA rows appear for all CG stores after execution.
--
-- 2. Add Store to Coverage Group with live/non-imported employee:
--    Confirm new plantilla_store_links row appears with coverage_group_id set.
--    Confirm ESA row appears via fn_sync_employee_store_allocations.
--
-- 3. Add Store to Coverage Group with no employee:
--    No ESA or PSL rows created (Coverage Group may exist with zero employees).
--
-- 4. Confirm Employee Stores tab matches Coverage Group stores:
--    SELECT * FROM employee_store_allocations WHERE roving_group_id = '<cg_id>';
--
-- 5. Confirm Vacancy Open suppresses added store when CG has active employee/applicant:
--    SELECT * FROM vw_slot_derived_vacancy_shadow WHERE store_id = '<added_store_id>';
--    Should be suppressed if CG has active ESA.
--
-- 6. Confirm standalone Vacancy remains when CG has no employee/applicant.
--
-- 7. Confirm HC share recomputes after Add Store:
--    SELECT hc_share FROM coverage_group_stores WHERE coverage_group_id = '<cg_id>';
--
-- 8. Confirm Create Coverage Group still promotes eligible employees (regression).
--
-- 9. Confirm Remove Store still works (regression).
--
-- 10. Confirm Dissolve Coverage Group still works (regression).
--
-- 11. Re-run reconciliation and confirm no-op:
--    SELECT fn_reconcile_all_coverage_groups();
--    -- psl_inserted = 0, esa_inserted = 0
-- ============================================================================
