-- ============================================================
-- OHM2026_2058 — Deactivation Request v2 — Data Migration
-- Migration:  20260524120000_deactivation_v2_data_migration.sql
-- Depends on: 20260524100000 (foundation)
--             20260524110000 (RPCs + view)
-- ============================================================
-- Sections:
--   §1  Rename legacy 'For Deactivation' → 'Pending Deactivation'
--   §2  Backfill employee_deactivation_requests for existing rows
--   §3  Update v_plantilla_safe to include inactive_visible_until filter
--
-- Preservation:
--   - deactivation_requests, deactivation_batches, deactivation_items,
--     deactivation_audit_log (legacy tables) are NOT touched.
--   - uq_plantilla_employee_no_active unique index currently references
--     'For Deactivation' — must be updated to 'Pending Deactivation'.
--
-- Validation Queries (run manually after applying):
--   V1 – No remaining 'For Deactivation' rows in plantilla
--     SELECT COUNT(*) FROM plantilla WHERE status = 'For Deactivation';
--     -- Expected: 0
--
--   V2 – Pending Deactivation rows have request rows
--     SELECT p.id, p.status, edr.id AS request_id
--     FROM plantilla p
--     LEFT JOIN employee_deactivation_requests edr
--       ON edr.plantilla_id = p.id AND edr.status = 'Pending' AND edr.is_archived = false
--     WHERE p.status = 'Pending Deactivation'
--       AND COALESCE(p.is_deleted, false) = false;
--
--   V3 – Orphaned rows (no requestor) reported but not failed
--     -- Check RAISE NOTICE output in migration logs for "Orphaned row" messages.
--
--   V4 – v_plantilla_safe WHERE clause includes inactive_visible_until
--     SELECT pg_get_viewdef('public.v_plantilla_safe', true);
--     -- Must contain: inactive_visible_until IS NULL OR inactive_visible_until > now()
--
--   V5 – unique index updated for new status name
--     SELECT indexdef FROM pg_indexes
--     WHERE tablename = 'plantilla'
--       AND indexname = 'uq_plantilla_employee_no_active';
--     -- Must NOT contain 'For Deactivation'; must contain 'Pending Deactivation'.
--
--   V6 – inactive_visible_until backfilled for non-null requestors
--     SELECT COUNT(*) FROM plantilla
--     WHERE status = 'Pending Deactivation'
--       AND inactive_visible_until IS NULL
--       AND COALESCE(is_deleted, false) = false;
--     -- Expected: 0 (all Pending Deactivation rows have a window set)
-- ============================================================


-- ============================================================
-- §1  Rename 'For Deactivation' → 'Pending Deactivation'
-- ============================================================
-- Update the unique index first since it constrains status values,
-- then rename the status column values.

-- Drop the existing unique index that hard-codes 'For Deactivation'
DROP INDEX IF EXISTS public.uq_plantilla_employee_no_active;

-- Recreate with updated status list (Pending Deactivation replaces For Deactivation)
CREATE UNIQUE INDEX uq_plantilla_employee_no_active
  ON public.plantilla(employee_no)
  WHERE
    is_deleted = false
    AND status = ANY(ARRAY[
      'Active',
      'Pending Deactivation',
      'On Leave'
    ]);

-- Rename the status on all affected rows
DO $$
DECLARE
  v_count int;
BEGIN
  UPDATE public.plantilla
    SET status     = 'Pending Deactivation',
        updated_at = NOW()
  WHERE status = 'For Deactivation'
    AND COALESCE(is_deleted, false) = false;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE '[§1] Renamed % row(s) from ''For Deactivation'' → ''Pending Deactivation''', v_count;
END;
$$;


-- ============================================================
-- §2  Backfill employee_deactivation_requests
-- ============================================================
-- For each 'Pending Deactivation' plantilla row that was just renamed
-- from 'For Deactivation', create a synthetic request row if none
-- exists yet. Use existing for_deactivation_by / for_deactivation_at
-- to attribute the request correctly.
--
-- Rows where for_deactivation_by IS NULL are considered orphaned:
--   - Status rename is preserved.
--   - No request row is inserted (no requestor to attribute to).
--   - A NOTICE is raised for manual review.
--   - inactive_visible_until is set to NOW() + 30d as a safe default.

DO $$
DECLARE
  v_row           RECORD;
  v_req_exists    boolean;
  v_group_id      uuid;
  v_backfill_count int := 0;
  v_orphan_count   int := 0;
BEGIN
  FOR v_row IN
    SELECT
      p.id,
      p.employee_name,
      p.employee_no,
      p.account,
      p.account_id,
      p.for_deactivation_by,
      p.for_deactivation_at,
      p.inactive_visible_until
    FROM public.plantilla p
    WHERE p.status = 'Pending Deactivation'
      AND COALESCE(p.is_deleted, false) = false
  LOOP
    -- Check if a request row already exists for this plantilla_id
    SELECT EXISTS (
      SELECT 1 FROM public.employee_deactivation_requests
      WHERE plantilla_id = v_row.id
        AND status = 'Pending'
        AND is_archived = false
    ) INTO v_req_exists;

    IF v_req_exists THEN
      CONTINUE;  -- Already has a Pending request row; skip
    END IF;

    -- Ensure inactive_visible_until is set (may have been NULL pre-migration)
    IF v_row.inactive_visible_until IS NULL THEN
      UPDATE public.plantilla SET
        inactive_visible_until = COALESCE(v_row.for_deactivation_at, NOW()) + INTERVAL '30 days',
        updated_at = NOW()
      WHERE id = v_row.id;
    END IF;

    IF v_row.for_deactivation_by IS NULL THEN
      -- Orphaned row — log and skip (no requestor attribution possible)
      v_orphan_count := v_orphan_count + 1;
      RAISE NOTICE '[§2] Orphaned Pending Deactivation row — no requestor: plantilla_id=%', v_row.id;
      CONTINUE;
    END IF;

    -- Resolve group_id from the requestor's user_scopes
    SELECT group_id INTO v_group_id
      FROM public.user_scopes
     WHERE user_id = v_row.for_deactivation_by
     LIMIT 1;

    -- Insert the synthetic backfill request row
    INSERT INTO public.employee_deactivation_requests (
      plantilla_id,
      requestor_profile_id,
      group_id,
      account_id,
      employee_name,
      employee_no,
      account_name,
      status,
      created_at,
      updated_at
    ) VALUES (
      v_row.id,
      v_row.for_deactivation_by,
      v_group_id,
      v_row.account_id,
      v_row.employee_name,
      v_row.employee_no,
      v_row.account,
      'Pending',
      COALESCE(v_row.for_deactivation_at, NOW()),
      NOW()
    )
    ON CONFLICT DO NOTHING;

    -- Audit the synthetic creation
    INSERT INTO public.employee_deactivation_audit_log (
      request_id,
      plantilla_id,
      action,
      performed_by_profile_id,
      performed_at,
      metadata
    )
    SELECT
      edr.id,
      v_row.id,
      'REQUEST_CREATED',
      v_row.for_deactivation_by,
      COALESCE(v_row.for_deactivation_at, NOW()),
      jsonb_build_object(
        'backfill', true,
        'employee_name', v_row.employee_name,
        'note', 'Synthetic row created during v2 data migration'
      )
    FROM public.employee_deactivation_requests edr
    WHERE edr.plantilla_id = v_row.id
      AND edr.status = 'Pending'
      AND edr.is_archived = false
    LIMIT 1;

    v_backfill_count := v_backfill_count + 1;
  END LOOP;

  RAISE NOTICE '[§2] Backfill complete: % request row(s) inserted, % orphaned row(s) skipped',
    v_backfill_count, v_orphan_count;
END;
$$;


-- ============================================================
-- §3  Update v_plantilla_safe
-- ============================================================
-- Add the inactive_visible_until filter so that Inactive tab
-- entries expire after their 30-day window.
-- Full column list is copied from the existing view definition;
-- only the WHERE clause is extended.

CREATE OR REPLACE VIEW public.v_plantilla_safe AS
SELECT
  id,
  employee_name,
  employee_no,
  account,
  account_id,
  chain_id,
  store_id,
  province_id,
  "position",
  position_id,
  status,
  separation_status,
  date_of_separation,
  over_headcount,
  deactivated_at,
  deactivated_visible_until,
  deactivation_reason,
  deletion_requested_at,
  deletion_reason,
  sss_no,
  philhealth_no,
  pagibig_no,
  CASE
    WHEN atm_no IS NULL THEN NULL::text
    WHEN length(atm_no) <= 4 THEN '****'::text
    ELSE repeat('*', length(atm_no) - 4) || right(atm_no, 4)
  END AS atm_no_masked,
  civil_status,
  date_of_birth,
  CASE
    WHEN date_of_birth IS NOT NULL
      THEN EXTRACT(year FROM age(date_of_birth::timestamptz))::integer
    ELSE NULL::integer
  END AS age,
  CASE
    WHEN date_hired IS NOT NULL
      THEN (EXTRACT(epoch FROM age(now(), date_hired::timestamptz))
           / (60 * 60 * 24 * 30.4375))::integer
    ELSE NULL::integer
  END AS tenure_months,
  last_mika_synced_at,
  last_mika_synced_by,
  store_name,
  area,
  rate,
  schedule,
  deployment_type,
  has_penalty,
  date_hired,
  coordinator,
  hrco_name,
  vcode,
  hr_emploc_id,
  roving_assignment_id,
  created_at,
  updated_at,
  source_headcount_request_id,
  -- v2 additions
  -- Computed columns
  COALESCE((
    SELECT COUNT(*)
      FROM public.plantilla_store_links psl
     WHERE psl.plantilla_id = p.id
       AND psl.deleted_at IS NULL
       AND psl.status = 'Active'
  ), 0)::integer AS roving_store_count,
  (
    SELECT jsonb_agg(
      jsonb_build_object(
        'vcode',     psl.vcode,
        'store_name',psl.store_name,
        'account',   psl.account,
        'status',    psl.status,
        'linked_at', psl.linked_at
      ) ORDER BY psl.vcode
    )
      FROM public.plantilla_store_links psl
     WHERE psl.plantilla_id = p.id
       AND psl.deleted_at IS NULL
  ) AS roving_stores,
  inactive_visible_until
FROM public.plantilla p
WHERE
  COALESCE(is_deleted, false) = false
  AND (deactivated_visible_until IS NULL OR deactivated_visible_until > NOW())
  -- v2 addition: expire Inactive tab entries after their 30-day window
  AND (inactive_visible_until IS NULL OR inactive_visible_until > NOW());

COMMENT ON VIEW public.v_plantilla_safe IS
  'Safe read-only view over plantilla. Excludes deleted rows, '
  'expired deactivated-visibility windows, and expired inactive-visibility windows. '
  'inactive_visible_until filter added in 20260524120000 (v2 data migration).';
