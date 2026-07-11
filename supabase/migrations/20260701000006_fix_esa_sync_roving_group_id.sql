-- Migration: 20260701000006_fix_esa_sync_roving_group_id
-- Created: 2026-07-01
-- Purpose: fn_sync_employee_store_allocations hardcoded roving_group_id = NULL on every
--          INSERT, so non-imported Coverage Group roving employees never got their active
--          employee_store_allocations rows linked back to coverage_groups — causing the
--          Coverage Group card to silently disappear from the Stores tab on the Employee
--          Profile screen even though plantilla.coverage_group_id and
--          plantilla_store_links.coverage_group_id were both correctly set.
--
-- Smoke Tests:
-- S1: SELECT fn_sync_employee_store_allocations('2019-14522'); then
--     SELECT roving_group_id FROM employee_store_allocations
--     WHERE plantilla_id = '7e7bd087-9f0a-4d74-b9b5-552cf8c98019' AND is_active;
--     -> all 5 active rows must now show roving_group_id = '49d14067-8576-44a6-b0da-98cbf553ce5a'
-- S2: Re-run fn_sync_employee_store_allocations('2019-14521') (MAGDAONG) and confirm its
--     active rows are unaffected (still roving_group_id = '49d14067-...', filled_hc unchanged)

BEGIN;

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
    -- Coverage Group roving (coverage_group_id IS NOT NULL, roving_assignment_id IS NULL) --
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
           NULL::uuid AS store_id_hint, NULL::uuid AS account_id_hint,
           NULL::uuid AS coverage_group_id_hint
    FROM masters m
    JOIN public.plantilla_store_links psl
      ON psl.plantilla_id = m.plantilla_id
     AND psl.status = 'Active'
     AND psl.deleted_at IS NULL
    WHERE m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL
    UNION ALL
    SELECT m.plantilla_id, hsl.vcode, hsl.store_name,
           NULL::uuid AS store_id_hint, NULL::uuid AS account_id_hint,
           NULL::uuid AS coverage_group_id_hint
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
    -- Coverage Group roving --
    -- FIX: carry m.coverage_group_id through so the inserted allocation row can be
    -- linked back to its Coverage Group via roving_group_id (see INSERT below).
    SELECT m.plantilla_id, psl.vcode, psl.store_name,
           s.id AS store_id_hint, m.account_id AS account_id_hint,
           m.coverage_group_id AS coverage_group_id_hint
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
           m.store_id AS store_id_hint, m.account_id AS account_id_hint,
           NULL::uuid AS coverage_group_id_hint
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
           COALESCE(st.group_id, acc.group_id)                  AS group_id,
           f.coverage_group_id_hint                              AS roving_group_id
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
    r.plantilla_id, p_employee_no, r.roving_group_id,
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

-- ── Data repair: backfill already-active rows the unpatched function left NULL ──
-- fn_sync_employee_store_allocations only INSERTs rows for footprints not already
-- active (NOT EXISTS guard), so previously-inserted active rows with
-- roving_group_id = NULL are never touched by re-running the function. A direct
-- UPDATE is required to backfill them. Scope is identical to the function's own
-- Coverage Group roving branch: LIVE (non-imported) roving employees whose
-- plantilla.coverage_group_id is set and roving_assignment_id is NULL.
UPDATE public.employee_store_allocations e
SET roving_group_id = p.coverage_group_id
FROM public.plantilla p
WHERE e.plantilla_id = p.id
  AND e.is_active = true
  AND e.roving_group_id IS NULL
  AND p.deployment_type = 'Roving'
  AND p.coverage_group_id IS NOT NULL
  AND p.roving_assignment_id IS NULL
  AND p.is_deleted = false
  AND COALESCE(p.is_archived, false) = false
  AND p.source_employee_import_batch_id IS NULL
  AND p.source_baseline_import_batch_id IS NULL;

COMMIT;
