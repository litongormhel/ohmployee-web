-- ============================================================
-- OHM2026_0063 - Plantilla Import Batch Rollback V1
-- Migration:  20260626000000_plantilla_import_rollback_v1.sql
-- Depends on: 20260625000000_hydrate_plantilla_from_baseline_import.sql
-- ============================================================
-- Purpose
--   Adds safe rollback support for approved unified Plantilla Baseline Import
--   batches. Rollback reverses only rows created or modified by the exact
--   approved batch, using public.plantilla_import_commit_snapshots.
--
-- Safety model
--   - Head Admin / Super Admin only, via fn_can_approve_plantilla_import().
--   - SECURITY DEFINER with search_path pinned to public.
--   - Only status=approved can roll back.
--   - Entity DML is atomic inside an exception block. On failure, entity DML is
--     rolled back and the batch is marked rollback_failed with error detail.
--   - Later-import protection: if current plantilla/store/allocation state has
--     been superseded by another batch, rollback fails rather than clobbering
--     unrelated newer state.
--
-- Validation checklist (run after applying)
--   V1  RPC exists:
--         SELECT proname FROM pg_proc
--          WHERE proname = 'rollback_plantilla_import_batch';
--   V2  Status constraint includes rollback states:
--         SELECT pg_get_constraintdef(oid)
--           FROM pg_constraint WHERE conname = 'pib_status_check';
--   V3  Columns added:
--         SELECT column_name FROM information_schema.columns
--          WHERE table_name='plantilla_import_batches'
--            AND column_name IN (
--              'rolled_back_by','rolled_back_at','rollback_reason',
--              'rollback_error_detail'
--            );
--   V4  Rollback approved batch:
--         SELECT public.rollback_plantilla_import_batch('<batch_id>', 'test rollback');
--   V5  Batch rollback status:
--         SELECT status, rolled_back_at, rollback_reason
--           FROM plantilla_import_batches
--          WHERE id = '<batch_id>';
-- ============================================================


-- ============================================================
-- Section 1: Batch table rollback lifecycle metadata
-- ============================================================

ALTER TABLE public.plantilla_import_batches
  DROP CONSTRAINT IF EXISTS pib_status_check;

ALTER TABLE public.plantilla_import_batches
  ADD CONSTRAINT pib_status_check CHECK (
    status IN (
      'draft_uploaded',
      'validation_failed',
      'pending_approval',
      'approved',
      'rejected',
      'commit_failed',
      'rollback_pending',
      'rolled_back',
      'rollback_failed'
    )
  );

ALTER TABLE public.plantilla_import_batches
  ADD COLUMN IF NOT EXISTS rolled_back_by uuid,
  ADD COLUMN IF NOT EXISTS rolled_back_at timestamptz,
  ADD COLUMN IF NOT EXISTS rollback_reason text,
  ADD COLUMN IF NOT EXISTS rollback_error_detail text;

COMMENT ON COLUMN public.plantilla_import_batches.rolled_back_by IS
  'auth.uid() that successfully rolled back an approved Plantilla baseline import batch.';
COMMENT ON COLUMN public.plantilla_import_batches.rolled_back_at IS
  'Timestamp when an approved Plantilla baseline import batch was successfully rolled back.';
COMMENT ON COLUMN public.plantilla_import_batches.rollback_reason IS
  'Operator-supplied reason for rolling back an approved Plantilla baseline import batch.';
COMMENT ON COLUMN public.plantilla_import_batches.rollback_error_detail IS
  'Populated when status=rollback_failed: SQL error message from rollback_plantilla_import_batch.';

CREATE INDEX IF NOT EXISTS idx_pib_rollback_status
  ON public.plantilla_import_batches(status)
  WHERE status IN ('rollback_pending','rolled_back','rollback_failed');


-- ============================================================
-- Section 2: rollback_plantilla_import_batch
-- ============================================================

CREATE OR REPLACE FUNCTION public.rollback_plantilla_import_batch(
  p_batch_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid   uuid := auth.uid();
  v_actor uuid := public.get_current_profile_id();
  v_batch public.plantilla_import_batches%ROWTYPE;
  v_reason text := NULLIF(trim(COALESCE(p_reason, '')), '');
  v_archive_reason text;

  v_plantilla_restored int := 0;
  v_plantilla_archived int := 0;
  v_stores_restored int := 0;
  v_stores_deactivated int := 0;
  v_allocations_restored int := 0;
  v_allocations_deactivated int := 0;
  v_roving_groups_archived int := 0;
BEGIN
  -- Auth
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- Lock + state check
  SELECT * INTO v_batch
    FROM public.plantilla_import_batches
   WHERE id = p_batch_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'INVALID_STATE: only approved batches can be rolled back (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  IF NOT COALESCE(v_batch.rollback_ready, false) THEN
    RAISE EXCEPTION 'ROLLBACK_NOT_READY: batch has no completed rollback lineage'
      USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM public.plantilla_import_commit_snapshots s
     WHERE s.batch_id = p_batch_id
  ) THEN
    RAISE EXCEPTION 'ROLLBACK_NOT_READY: no commit snapshots found for batch'
      USING ERRCODE = '22023';
  END IF;

  v_archive_reason := 'Import batch rollback'
    || CASE WHEN v_reason IS NULL THEN '' ELSE ': ' || v_reason END;

  UPDATE public.plantilla_import_batches
     SET status = 'rollback_pending',
         rollback_error_detail = NULL,
         rollback_reason = v_reason,
         updated_at = now()
   WHERE id = p_batch_id;

  -- Entity rollback block. Any error rolls back all entity changes.
  BEGIN
    -- Refuse to restore older state if another import has superseded this one.
    IF EXISTS (
      SELECT 1
        FROM public.plantilla_import_commit_snapshots s
        JOIN public.plantilla p ON p.id = s.entity_id
       WHERE s.batch_id = p_batch_id
         AND s.entity_type = 'plantilla'
         AND s.action = 'update'
         AND (
           p.source_baseline_import_batch_id IS DISTINCT FROM p_batch_id
           OR p.updated_at > COALESCE(v_batch.approved_at, v_batch.updated_at)
         )
    ) THEN
      RAISE EXCEPTION 'ROLLBACK_UNSAFE: plantilla state has been superseded after batch %',
        p_batch_id USING ERRCODE = '40001';
    END IF;

    IF EXISTS (
      SELECT 1
        FROM public.plantilla_import_commit_snapshots s
        JOIN public.stores st ON st.id = s.entity_id
       WHERE s.batch_id = p_batch_id
         AND s.entity_type = 'store'
         AND s.action = 'update'
         AND (
           st.source_import_id IS DISTINCT FROM p_batch_id
           OR st.updated_at > COALESCE(v_batch.approved_at, v_batch.updated_at)
         )
    ) THEN
      RAISE EXCEPTION 'ROLLBACK_UNSAFE: store state has been superseded after batch %',
        p_batch_id USING ERRCODE = '40001';
    END IF;

    IF EXISTS (
      SELECT 1
        FROM (
          SELECT DISTINCT employee_no
            FROM public.plantilla_import_rows
           WHERE batch_id = p_batch_id
             AND validation_status IN ('valid','flagged')
             AND employee_no IS NOT NULL
        ) emp
        JOIN public.employee_store_allocations a
          ON a.employee_no = emp.employee_no
         AND a.account_id = v_batch.selected_account_id
         AND a.is_active
       WHERE a.source_import_batch_id IS DISTINCT FROM p_batch_id
    ) THEN
      RAISE EXCEPTION 'ROLLBACK_UNSAFE: active allocations have been superseded after batch %',
        p_batch_id USING ERRCODE = '40001';
    END IF;

    -- Batch-created allocations: preserve history, deactivate only.
    -- Approval lineage for inserted allocations is source_import_batch_id.
    UPDATE public.employee_store_allocations a
       SET is_active = false,
           effective_end = CURRENT_DATE
     WHERE a.source_import_batch_id = p_batch_id
       AND a.is_active;
    GET DIAGNOSTICS v_allocations_deactivated = ROW_COUNT;

    -- Batch-updated allocations: restore the exact prior allocation rows.
    WITH snap AS (
      SELECT
        s.entity_id,
        jsonb_populate_record(NULL::public.employee_store_allocations, s.previous_snapshot) AS r
      FROM public.plantilla_import_commit_snapshots s
      WHERE s.batch_id = p_batch_id
        AND s.entity_type = 'allocation'
        AND s.action = 'update'
        AND s.previous_snapshot IS NOT NULL
    )
    UPDATE public.employee_store_allocations a
       SET plantilla_id = (snap.r).plantilla_id,
           employee_no = (snap.r).employee_no,
           roving_group_id = (snap.r).roving_group_id,
           store_id = (snap.r).store_id,
           vcode = (snap.r).vcode,
           store_name = (snap.r).store_name,
           account_id = (snap.r).account_id,
           group_id = (snap.r).group_id,
           filled_hc = (snap.r).filled_hc,
           active_store_count = (snap.r).active_store_count,
           effective_start = (snap.r).effective_start,
           effective_end = (snap.r).effective_end,
           is_active = (snap.r).is_active,
           source_import_batch_id = (snap.r).source_import_batch_id,
           created_at = (snap.r).created_at,
           created_by = (snap.r).created_by
      FROM snap
     WHERE a.id = snap.entity_id;
    GET DIAGNOSTICS v_allocations_restored = ROW_COUNT;

    -- Batch-created plantilla rows: soft archive, never hard delete.
    UPDATE public.plantilla p
       SET is_archived = true,
           archived_at = now(),
           archived_by = v_actor,
           archive_reason = v_archive_reason,
           status = 'Inactive',
           updated_at = now(),
           updated_by = v_actor
      FROM public.plantilla_import_commit_snapshots s
     WHERE s.batch_id = p_batch_id
       AND s.entity_type = 'plantilla'
       AND s.action = 'insert'
       AND s.entity_id = p.id
       AND p.source_baseline_import_batch_id = p_batch_id
       AND COALESCE(p.is_archived, false) = false;
    GET DIAGNOSTICS v_plantilla_archived = ROW_COUNT;

    -- Batch-updated plantilla rows: restore the prior row snapshot.
    WITH snap AS (
      SELECT
        s.entity_id,
        jsonb_populate_record(NULL::public.plantilla, s.previous_snapshot) AS r
      FROM public.plantilla_import_commit_snapshots s
      WHERE s.batch_id = p_batch_id
        AND s.entity_type = 'plantilla'
        AND s.action = 'update'
        AND s.previous_snapshot IS NOT NULL
    )
    UPDATE public.plantilla p
       SET employee_name = (snap.r).employee_name,
           employee_no = (snap.r).employee_no,
           account = (snap.r).account,
           status = (snap.r).status,
           emploc_no = (snap.r).emploc_no,
           vcode = (snap.r).vcode,
           position = (snap.r).position,
           created_at = (snap.r).created_at,
           hr_emploc_id = (snap.r).hr_emploc_id,
           vacancy_id = (snap.r).vacancy_id,
           vacancy_code_snapshot = (snap.r).vacancy_code_snapshot,
           employee_name_snapshot = (snap.r).employee_name_snapshot,
           account_id = (snap.r).account_id,
           chain_id = (snap.r).chain_id,
           store_id = (snap.r).store_id,
           province_id = (snap.r).province_id,
           area_name_snapshot = (snap.r).area_name_snapshot,
           hrco_user_id_snapshot = (snap.r).hrco_user_id_snapshot,
           om_user_id_snapshot = (snap.r).om_user_id_snapshot,
           atl_user_id_snapshot = (snap.r).atl_user_id_snapshot,
           position_id = (snap.r).position_id,
           rest_day = (snap.r).rest_day,
           resignation_date = (snap.r).resignation_date,
           remarks = (snap.r).remarks,
           moved_by_user_id = (snap.r).moved_by_user_id,
           created_by = (snap.r).created_by,
           updated_at = (snap.r).updated_at,
           updated_by = (snap.r).updated_by,
           store_name = (snap.r).store_name,
           area = (snap.r).area,
           rate = (snap.r).rate,
           schedule = (snap.r).schedule,
           deployment_type = (snap.r).deployment_type,
           has_penalty = (snap.r).has_penalty,
           date_hired = (snap.r).date_hired,
           coordinator = (snap.r).coordinator,
           hrco_name = (snap.r).hrco_name,
           last_name = (snap.r).last_name,
           first_name = (snap.r).first_name,
           middle_name = (snap.r).middle_name,
           date_of_separation = (snap.r).date_of_separation,
           separation_status = (snap.r).separation_status,
           tagged_at = (snap.r).tagged_at,
           inactive_at = (snap.r).inactive_at,
           inactive_by = (snap.r).inactive_by,
           for_deactivation_at = (snap.r).for_deactivation_at,
           for_deactivation_by = (snap.r).for_deactivation_by,
           deactivated_at = (snap.r).deactivated_at,
           deactivated_by = (snap.r).deactivated_by,
           deactivated_visible_until = (snap.r).deactivated_visible_until,
           last_mika_synced_at = (snap.r).last_mika_synced_at,
           last_mika_synced_by = (snap.r).last_mika_synced_by,
           source_headcount_request_id = (snap.r).source_headcount_request_id,
           is_deleted = (snap.r).is_deleted,
           over_headcount = (snap.r).over_headcount,
           deactivation_reason = (snap.r).deactivation_reason,
           deletion_requested_at = (snap.r).deletion_requested_at,
           deletion_requested_by = (snap.r).deletion_requested_by,
           deletion_reason = (snap.r).deletion_reason,
           deletion_remarks = (snap.r).deletion_remarks,
           deletion_approved_at = (snap.r).deletion_approved_at,
           deletion_approved_by = (snap.r).deletion_approved_by,
           sss_no = (snap.r).sss_no,
           philhealth_no = (snap.r).philhealth_no,
           pagibig_no = (snap.r).pagibig_no,
           atm_no = (snap.r).atm_no,
           civil_status = (snap.r).civil_status,
           date_of_birth = (snap.r).date_of_birth,
           transferred_from_store_id = (snap.r).transferred_from_store_id,
           last_transfer_at = (snap.r).last_transfer_at,
           last_transfer_by = (snap.r).last_transfer_by,
           inactive_visible_until = (snap.r).inactive_visible_until,
           is_archived = (snap.r).is_archived,
           archived_at = (snap.r).archived_at,
           archived_by = (snap.r).archived_by,
           archive_reason = (snap.r).archive_reason,
           restored_at = (snap.r).restored_at,
           restored_by = (snap.r).restored_by,
           source_baseline_import_batch_id = (snap.r).source_baseline_import_batch_id,
           roving_assignment_id = (snap.r).roving_assignment_id,
           is_pool_employee = (snap.r).is_pool_employee
      FROM snap
     WHERE p.id = snap.entity_id
       AND p.source_baseline_import_batch_id = p_batch_id;
    GET DIAGNOSTICS v_plantilla_restored = ROW_COUNT;

    -- Batch-updated stores: restore the prior row snapshot.
    WITH snap AS (
      SELECT
        s.entity_id,
        jsonb_populate_record(NULL::public.stores, s.previous_snapshot) AS r
      FROM public.plantilla_import_commit_snapshots s
      WHERE s.batch_id = p_batch_id
        AND s.entity_type = 'store'
        AND s.action = 'update'
        AND s.previous_snapshot IS NOT NULL
    )
    UPDATE public.stores st
       SET account_id = (snap.r).account_id,
           store_name = (snap.r).store_name,
           store_branch = (snap.r).store_branch,
           area_city = (snap.r).area_city,
           province = (snap.r).province,
           is_active = (snap.r).is_active,
           created_at = (snap.r).created_at,
           updated_at = (snap.r).updated_at,
           group_id = (snap.r).group_id,
           hrco_user_id = (snap.r).hrco_user_id,
           om_user_id = (snap.r).om_user_id,
           vcode = (snap.r).vcode,
           area_province = (snap.r).area_province,
           type = (snap.r).type,
           with_penalty = (snap.r).with_penalty,
           status = (snap.r).status,
           created_by = (snap.r).created_by,
           updated_by = (snap.r).updated_by,
           approved_by = (snap.r).approved_by,
           approved_at = (snap.r).approved_at,
           source_import_id = (snap.r).source_import_id,
           employment_type = (snap.r).employment_type
      FROM snap
     WHERE st.id = snap.entity_id
       AND st.source_import_id = p_batch_id;
    GET DIAGNOSTICS v_stores_restored = ROW_COUNT;

    -- Batch-created stores: deactivate only when no active plantilla/allocation remains.
    UPDATE public.stores st
       SET is_active = false,
           status = 'archived',
           updated_at = now(),
           updated_by = v_actor
      FROM public.plantilla_import_commit_snapshots s
     WHERE s.batch_id = p_batch_id
       AND s.entity_type = 'store'
       AND s.action = 'insert'
       AND s.entity_id = st.id
       AND st.source_import_id = p_batch_id
       AND NOT EXISTS (
         SELECT 1
           FROM public.plantilla p
          WHERE p.store_id = st.id
            AND p.status IN ('Active','Pending Deactivation','On Leave','For Deactivation')
            AND COALESCE(p.is_archived, false) = false
            AND COALESCE(p.is_deleted, false) = false
       )
       AND NOT EXISTS (
         SELECT 1
           FROM public.employee_store_allocations a
          WHERE a.store_id = st.id
            AND a.is_active
       );
    GET DIAGNOSTICS v_stores_deactivated = ROW_COUNT;

    -- Roving groups created by this batch: close them if no active allocations remain.
    UPDATE public.import_roving_groups g
       SET archived_at = COALESCE(g.archived_at, now()),
           updated_at = now()
     WHERE g.source_import_batch_id = p_batch_id
       AND NOT EXISTS (
         SELECT 1
           FROM public.employee_store_allocations a
          WHERE a.roving_group_id = g.id
            AND a.is_active
       );
    GET DIAGNOSTICS v_roving_groups_archived = ROW_COUNT;

    -- Mark rollback success and audit with a valid audit_action enum.
    UPDATE public.plantilla_import_batches
       SET status = 'rolled_back',
           rolled_back_by = v_uid,
           rolled_back_at = now(),
           rollback_reason = v_reason,
           rollback_error_detail = NULL,
           updated_at = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, old_data, new_data)
    VALUES (
      v_uid,
      'plantilla_import_batches',
      'UPDATE',
      p_batch_id,
      jsonb_build_object('status', 'approved'),
      jsonb_build_object(
        'status', 'rolled_back',
        'batch_id', p_batch_id,
        'plantilla_restored', v_plantilla_restored,
        'plantilla_archived', v_plantilla_archived,
        'stores_restored', v_stores_restored,
        'stores_deactivated', v_stores_deactivated,
        'allocations_restored', v_allocations_restored,
        'allocations_deactivated', v_allocations_deactivated,
        'roving_groups_archived', v_roving_groups_archived,
        'reason', v_reason
      )
    );

    RETURN jsonb_build_object(
      'status', 'rolled_back',
      'batch_id', p_batch_id,
      'plantilla_restored', v_plantilla_restored,
      'plantilla_archived', v_plantilla_archived,
      'stores_restored', v_stores_restored,
      'stores_deactivated', v_stores_deactivated,
      'allocations_restored', v_allocations_restored,
      'allocations_deactivated', v_allocations_deactivated,
      'reason', v_reason
    );

  EXCEPTION WHEN OTHERS THEN
    UPDATE public.plantilla_import_batches
       SET status = 'rollback_failed',
           rollback_error_detail = format('[%s] %s', SQLSTATE, SQLERRM),
           rollback_reason = v_reason,
           updated_at = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, old_data, new_data)
    VALUES (
      v_uid,
      'plantilla_import_batches',
      'UPDATE',
      p_batch_id,
      jsonb_build_object('status', 'approved'),
      jsonb_build_object(
        'status', 'rollback_failed',
        'batch_id', p_batch_id,
        'error', format('[%s] %s', SQLSTATE, SQLERRM),
        'reason', v_reason
      )
    );

    RETURN jsonb_build_object(
      'status', 'rollback_failed',
      'batch_id', p_batch_id,
      'error', format('[%s] %s', SQLSTATE, SQLERRM),
      'reason', v_reason
    );
  END;
END;
$func$;

REVOKE ALL ON FUNCTION public.rollback_plantilla_import_batch(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rollback_plantilla_import_batch(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.rollback_plantilla_import_batch(uuid, text) IS
  'Rolls back one approved unified Plantilla Baseline Import batch using commit snapshots. '
  'Created rows are archived/deactivated; updated rows are restored from previous_snapshot. '
  'RBAC: Head Admin / Super Admin only.';
