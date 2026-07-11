-- ============================================================
-- OHM2026_0079 — Plantilla Import Operational Safeguards
-- Migration:  20260704000000_plantilla_import_operational_safeguards.sql
-- Depends on: 20260626000000_plantilla_import_rollback_v1.sql
--             20260625000000_hydrate_plantilla_from_baseline_import.sql
-- ============================================================
-- Purpose
--   Production-grade operational safeguards for the Plantilla Baseline Import
--   approval and rollback lifecycle. Additive only — no existing table columns,
--   index names, or RPC signatures are changed.
--
-- Sections
--   §1  Schema additions to plantilla_import_batches
--   §2  mark_expired_plantilla_import_batches (stale batch cleanup)
--   §3  approve_plantilla_import_batch (hardened — carries forward OHM2026_0060)
--   §4  rollback_plantilla_import_batch (hardened — carries forward OHM2026_0063)
--   §5  get_plantilla_import_operational_health (SA/HA health RPC)
--
-- Replay safety
--   All column additions use ADD COLUMN IF NOT EXISTS.
--   All functions use CREATE OR REPLACE.
--   Status constraint is dropped and re-created to add 'expired'.
--   No DROP CASCADE anywhere.
--
-- What is NOT changed
--   - Allocation formulas / fractional HC math
--   - Roving detection and import_roving_groups logic
--   - Commit snapshot structure (plantilla_import_commit_snapshots)
--   - Diff preview RPC (get_plantilla_import_diff_preview)
--   - CENCOM, Vacancy, HR Emploc, or any other module
--   - Existing rollback snapshot semantics
--
-- Validation checklist (run after applying)
--   V1  New columns exist:
--         SELECT column_name FROM information_schema.columns
--          WHERE table_name = 'plantilla_import_batches'
--            AND column_name IN (
--              'expired_at','is_expired','approver_role','rollback_role',
--              'approval_latency_seconds','rollback_latency_seconds'
--            );
--   V2  Status constraint includes 'expired':
--         SELECT pg_get_constraintdef(oid)
--           FROM pg_constraint WHERE conname = 'pib_status_check';
--   V3  Double-approval lock: call approve twice on the same pending batch —
--         first succeeds, second returns 'Batch already processed.'
--   V4  Expired batch guard: manually set is_expired=true on a pending batch,
--         then call approve → 'Batch has expired and cannot be approved.'
--   V5  Superseded approval guard: approve batch A (same group+account), then
--         try to approve older batch B → 'Batch superseded by newer approved import.'
--   V6  Stale expiration: run mark_expired_plantilla_import_batches(0) →
--         all pending batches transition to 'expired'.
--   V7  Rollback concurrency: verify rollback on a rolled_back batch returns
--         INVALID_STATE and does NOT clobber the batch.
--   V8  Rollback superseded: approve two batches for same scope, rollback the
--         older one → 'ROLLBACK_UNSAFE: a newer approved import batch exists for this scope.'
--   V9  Audit enrichment: after approval check approver_role, approval_latency_seconds.
--   V10 Health RPC: SELECT get_plantilla_import_operational_health();
-- ============================================================


-- ============================================================
-- §1  Schema additions to plantilla_import_batches
-- ============================================================

-- Status constraint: add 'expired' to the lifecycle
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
      'rollback_failed',
      'expired'
    )
  );

-- Stale batch expiration tracking
ALTER TABLE public.plantilla_import_batches
  ADD COLUMN IF NOT EXISTS expired_at            timestamptz,
  ADD COLUMN IF NOT EXISTS is_expired            boolean NOT NULL DEFAULT false;

-- Operational audit enrichment
ALTER TABLE public.plantilla_import_batches
  ADD COLUMN IF NOT EXISTS approver_role          text,
  ADD COLUMN IF NOT EXISTS rollback_role          text,
  ADD COLUMN IF NOT EXISTS approval_latency_seconds  numeric(10,2),
  ADD COLUMN IF NOT EXISTS rollback_latency_seconds  numeric(10,2);

COMMENT ON COLUMN public.plantilla_import_batches.expired_at IS
  'Timestamp when this batch was marked expired (stale pending batch expiration).';
COMMENT ON COLUMN public.plantilla_import_batches.is_expired IS
  'True if this batch has been marked expired by mark_expired_plantilla_import_batches or the approval guard.';
COMMENT ON COLUMN public.plantilla_import_batches.approver_role IS
  'Role of the user who approved this batch (populated on successful approval).';
COMMENT ON COLUMN public.plantilla_import_batches.rollback_role IS
  'Role of the user who rolled back this batch (populated on successful rollback).';
COMMENT ON COLUMN public.plantilla_import_batches.approval_latency_seconds IS
  'Elapsed seconds from batch created_at to approved_at (operational SLA metric).';
COMMENT ON COLUMN public.plantilla_import_batches.rollback_latency_seconds IS
  'Elapsed seconds from approved_at to rolled_back_at (rollback turnaround metric).';

CREATE INDEX IF NOT EXISTS idx_pib_expired
  ON public.plantilla_import_batches(is_expired, created_at)
  WHERE is_expired = true;

CREATE INDEX IF NOT EXISTS idx_pib_stale_pending
  ON public.plantilla_import_batches(created_at)
  WHERE status = 'pending_approval' AND is_expired = false;


-- ============================================================
-- §2  mark_expired_plantilla_import_batches
-- ============================================================
-- Marks pending batches older than the configurable threshold as expired.
-- No cron is wired yet. Can be called manually or from an Edge Function sweep.
-- SA/HA only.

CREATE OR REPLACE FUNCTION public.mark_expired_plantilla_import_batches(
  p_threshold_hours int DEFAULT 72
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid       uuid := auth.uid();
  v_expired   int;
  v_cutoff    timestamptz := now() - (p_threshold_hours || ' hours')::interval;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  IF p_threshold_hours < 1 THEN
    RAISE EXCEPTION 'INVALID_INPUT: threshold_hours must be >= 1'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.plantilla_import_batches
     SET status     = 'expired',
         is_expired = true,
         expired_at = now(),
         updated_at = now()
   WHERE status = 'pending_approval'
     AND is_expired = false
     AND created_at < v_cutoff;

  GET DIAGNOSTICS v_expired = ROW_COUNT;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'plantilla_import_batches', 'UPDATE', NULL,
    jsonb_build_object(
      'action',           'mark_expired',
      'threshold_hours',  p_threshold_hours,
      'expired_count',    v_expired,
      'cutoff',           v_cutoff
    ));

  RETURN jsonb_build_object(
    'expired_count',   v_expired,
    'threshold_hours', p_threshold_hours,
    'cutoff',          v_cutoff
  );
END$func$;

REVOKE ALL ON FUNCTION public.mark_expired_plantilla_import_batches(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_expired_plantilla_import_batches(int) TO authenticated;

COMMENT ON FUNCTION public.mark_expired_plantilla_import_batches(int) IS
  'Marks stale pending_approval import batches as expired. Default threshold 72 hours. '
  'No cron wired yet — call manually or from a scheduled Edge Function sweep. '
  'RBAC: Head Admin / Super Admin only.';


-- ============================================================
-- §3  approve_plantilla_import_batch  (hardened)
-- ============================================================
-- Carries forward all OHM2026_0060 commit + hydration logic.
-- Adds:
--   - pg_advisory_xact_lock for approval/rollback mutual exclusion per batch
--   - Expired batch check (rejects with explicit error)
--   - Superseded batch check (newer approved batch in same group+account scope)
--   - Explicit 'Batch already processed.' error for terminal-state conflicts
--   - approver_role and approval_latency_seconds populated on success
--   - Enriched batch-level audit metadata

CREATE OR REPLACE FUNCTION public.approve_plantilla_import_batch(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid        uuid := auth.uid();
  v_actor      uuid := public.get_current_profile_id();
  v_batch      public.plantilla_import_batches%ROWTYPE;
  v_acct_name  text;
  v_caller_role text;

  -- Phase A locals
  v_srow               record;
  v_existing_store_id  uuid;
  v_new_store_id       uuid;
  v_old_store_snap     jsonb;
  v_pen_bool           boolean;
  v_emp_type_norm      text;
  v_stores_done        int := 0;
  v_rep_row_id         uuid;

  -- Phase B locals
  v_emp_rec        record;
  v_store_rec      record;
  v_plantilla_id   uuid;
  v_roving_id      uuid;
  v_store_cnt      int;
  v_filled         numeric(8,4);
  v_emp_name       text;
  v_old_plant_snap jsonb;
  v_employees_done int := 0;
  v_alloc_done     int := 0;

  -- Commit counts
  v_committable int;

  -- VCODE resolution guard
  v_unresolved_vcode text;
BEGIN
  -- ── Auth ─────────────────────────────────────────────────────────────────
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Caller role (for audit enrichment) ───────────────────────────────────
  v_caller_role := public.get_my_role();

  -- ── Advisory lock: serialise concurrent approval/rollback for this batch ──
  -- Prevents double-approval races and approval-during-rollback conflicts.
  -- Lock is held for the duration of this transaction and auto-released on commit/rollback.
  PERFORM pg_advisory_xact_lock(4207900, hashtext(p_batch_id::text));

  -- ── Lock + state check ───────────────────────────────────────────────────
  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  -- Terminal-state guard: explicit "Batch already processed." for concurrency races
  IF v_batch.status IN ('approved', 'rolled_back', 'rollback_pending', 'rollback_failed') THEN
    RAISE EXCEPTION 'Batch already processed.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Expired batch guard (both explicit flag and inline threshold check)
  IF v_batch.is_expired OR v_batch.status = 'expired'
     OR (v_batch.status = 'pending_approval'
         AND v_batch.created_at < now() - interval '72 hours')
  THEN
    -- Auto-mark if threshold exceeded but not yet marked
    IF NOT v_batch.is_expired AND v_batch.status <> 'expired' THEN
      UPDATE public.plantilla_import_batches
         SET status = 'expired', is_expired = true, expired_at = now(), updated_at = now()
       WHERE id = p_batch_id;
    END IF;
    RAISE EXCEPTION 'Batch has expired and cannot be approved.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Standard state guard
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  -- ── Superseded batch guard ───────────────────────────────────────────────
  -- Prevent approval if a newer approved import already exists for the same scope.
  IF EXISTS (
    SELECT 1
      FROM public.plantilla_import_batches newer
     WHERE newer.selected_group_id   = v_batch.selected_group_id
       AND newer.selected_account_id = v_batch.selected_account_id
       AND newer.status = 'approved'
       AND newer.approved_at > v_batch.created_at
       AND newer.id <> p_batch_id
  ) THEN
    RAISE EXCEPTION 'Batch superseded by newer approved import.'
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Pre-commit guard ─────────────────────────────────────────────────────
  SELECT count(*) INTO v_committable
    FROM public.plantilla_import_rows
   WHERE batch_id = p_batch_id
     AND validation_status IN ('valid','flagged')
     AND employee_no IS NOT NULL
     AND vcode IS NOT NULL;

  IF v_committable = 0 THEN
    RAISE EXCEPTION 'COMMIT_EMPTY: no committable rows in batch (valid+flagged with employee_no and vcode)'
      USING ERRCODE = '22023';
  END IF;

  SELECT account_name INTO v_acct_name
    FROM public.accounts WHERE id = v_batch.selected_account_id;

  -- ── Temp store commit map ─────────────────────────────────────────────────
  DROP TABLE IF EXISTS _pib_store_map;
  CREATE TEMP TABLE _pib_store_map (
    vcode    text,
    store_id uuid,
    is_new   boolean
  ) ON COMMIT DROP;

  -- ── Inner exception block — all commit DML is atomic ─────────────────────
  BEGIN

    -- ── Phase A: Store upsert ───────────────────────────────────────────────
    FOR v_srow IN
      SELECT DISTINCT ON (vcode)
             vcode, store_name, area_province, area_city,
             employment_type, with_penalty_raw, row_number, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid','flagged')
         AND vcode IS NOT NULL
       ORDER BY vcode, row_number
    LOOP
      v_emp_type_norm := CASE
        WHEN lower(COALESCE(v_srow.employment_type,'')) IN ('stationary','roving')
          THEN lower(v_srow.employment_type)
        ELSE NULL
      END;

      v_pen_bool := CASE
        WHEN lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('yes','y','true','1')  THEN true
        WHEN lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('no','n','false','0') THEN false
        ELSE NULL
      END;

      -- Capture pre-commit store snapshot for rollback lineage
      SELECT to_jsonb(s.*) INTO v_old_store_snap
        FROM public.stores s
       WHERE upper(s.vcode) = upper(v_srow.vcode) AND s.status = 'active'
       ORDER BY s.created_at LIMIT 1;

      IF v_old_store_snap IS NULL THEN
        -- New store: insert
        INSERT INTO public.stores (
          vcode, store_name, area_province, area_city,
          employment_type, with_penalty,
          group_id, account_id, status,
          created_by, updated_by, approved_by, approved_at, source_import_id
        ) VALUES (
          v_srow.vcode, v_srow.store_name, v_srow.area_province, v_srow.area_city,
          v_emp_type_norm, v_pen_bool,
          v_batch.selected_group_id, v_batch.selected_account_id, 'active',
          v_uid, v_uid, v_uid, now(), p_batch_id
        ) RETURNING id INTO v_new_store_id;

        INSERT INTO _pib_store_map VALUES (upper(v_srow.vcode), v_new_store_id, true);

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_new_store_id, 'insert', NULL, v_uid);

      ELSE
        -- Existing store: update
        v_existing_store_id := (v_old_store_snap->>'id')::uuid;

        UPDATE public.stores
           SET store_name      = v_srow.store_name,
               area_province   = v_srow.area_province,
               area_city       = v_srow.area_city,
               employment_type = COALESCE(v_emp_type_norm, employment_type),
               with_penalty    = COALESCE(v_pen_bool, with_penalty),
               updated_by      = v_uid,
               approved_by     = v_uid,
               approved_at     = now(),
               source_import_id = p_batch_id
         WHERE id = v_existing_store_id;

        INSERT INTO _pib_store_map VALUES (upper(v_srow.vcode), v_existing_store_id, false);

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_existing_store_id, 'update', v_old_store_snap, v_uid);
      END IF;

      UPDATE public.plantilla_import_rows
         SET previous_store_snapshot = v_old_store_snap
       WHERE batch_id = p_batch_id
         AND upper(vcode) = upper(v_srow.vcode)
         AND validation_status IN ('valid','flagged');

      v_stores_done := v_stores_done + 1;
    END LOOP;

    -- ── Post-Phase-A: VCODE resolution guard ─────────────────────────────────
    SELECT r.vcode INTO v_unresolved_vcode
      FROM public.plantilla_import_rows r
     WHERE r.batch_id = p_batch_id
       AND r.validation_status IN ('valid','flagged')
       AND r.vcode IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM _pib_store_map sm WHERE sm.vcode = upper(r.vcode)
       )
     LIMIT 1;

    IF v_unresolved_vcode IS NOT NULL THEN
      RAISE EXCEPTION 'STORE_RESOLUTION_FAILED: VCODE % not resolved after store upsert — cannot commit plantilla rows',
        v_unresolved_vcode
        USING ERRCODE = '23503';
    END IF;

    -- ── Phase B: Employee / plantilla upsert ────────────────────────────────
    FOR v_emp_rec IN
      WITH emp_rows AS (
        SELECT r.*
          FROM public.plantilla_import_rows r
         WHERE r.batch_id = p_batch_id
           AND r.validation_status IN ('valid','flagged')
           AND r.employee_no IS NOT NULL
      ),
      emp_summary AS (
        SELECT
          employee_no,
          count(DISTINCT vcode)        AS store_count,
          (array_agg(last_name ORDER BY row_number))[1]    AS last_name,
          (array_agg(first_name ORDER BY row_number))[1]   AS first_name,
          (array_agg(middle_name ORDER BY row_number))[1]  AS middle_name
        FROM emp_rows
        GROUP BY employee_no
      ),
      representative AS (
        SELECT DISTINCT ON (employee_no)
          employee_no,
          vcode,
          store_name,
          NULLIF(trim(position), '') AS position,
          CASE
            WHEN lower(COALESCE(employment_type,'')) = 'roving' THEN 'Roving'
            WHEN lower(COALESCE(employment_type,'')) = 'stationary' THEN 'Stationary'
            ELSE NULLIF(trim(employment_type), '')
          END AS deployment_type,
          CASE
            WHEN lower(COALESCE(with_penalty_raw,'')) IN ('yes','y','true','1') THEN true
            WHEN lower(COALESCE(with_penalty_raw,'')) IN ('no','n','false','0') THEN false
            ELSE NULL
          END AS has_penalty,
          NULLIF(trim(area_city), '') AS area_city,
          NULLIF(trim(area_province), '') AS area_province,
          NULLIF(
            concat_ws(', ', NULLIF(trim(area_city), ''), NULLIF(trim(area_province), '')),
            ''
          ) AS area_label
        FROM emp_rows
        ORDER BY employee_no, row_number
      )
      SELECT
        s.employee_no,
        s.store_count,
        s.last_name,
        s.first_name,
        s.middle_name,
        r.vcode,
        r.store_name,
        r.position,
        r.deployment_type,
        r.has_penalty,
        COALESCE(r.area_city, r.area_province) AS area,
        r.area_label AS area_name_snapshot
      FROM emp_summary s
      JOIN representative r ON r.employee_no = s.employee_no
    LOOP
      v_employees_done := v_employees_done + 1;
      v_store_cnt := v_emp_rec.store_count;
      v_filled    := round(1.0 / GREATEST(v_store_cnt, 1), 4);
      v_emp_name  := v_emp_rec.last_name || ', ' || v_emp_rec.first_name
                     || COALESCE(' ' || v_emp_rec.middle_name, '');

      -- Roving group for multi-store employees
      v_roving_id := NULL;
      IF v_store_cnt > 1 THEN
        INSERT INTO public.import_roving_groups (
          employee_no, account_id, group_id, account_name, label,
          active_store_count, filled_hc_per_store, source_import_batch_id, created_by
        ) VALUES (
          v_emp_rec.employee_no,
          v_batch.selected_account_id, v_batch.selected_group_id,
          v_acct_name, v_emp_name || ' — Roving',
          v_store_cnt, v_filled, p_batch_id, v_actor
        ) RETURNING id INTO v_roving_id;
      END IF;

      -- Resolve existing active plantilla master row for this employee
      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no
         AND is_deleted = false
         AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
       LIMIT 1;

      -- Capture pre-commit plantilla snapshot for rollback
      SELECT to_jsonb(p.*) INTO v_old_plant_snap
        FROM public.plantilla p WHERE id = v_plantilla_id;

      IF v_plantilla_id IS NULL THEN
        -- New employee: insert plantilla master.
        -- plantilla.vcode stays NULL: fk_plantilla_vcode → vacancies(vcode) and
        -- baseline VCODEs have no vacancy rows. Lineage is in employee_store_allocations.vcode.
        INSERT INTO public.plantilla (
          employee_name, employee_no, emploc_no, account, status,
          account_id, last_name, first_name, middle_name,
          roving_assignment_id, is_pool_employee,
          position, deployment_type, has_penalty, area, area_name_snapshot,
          vcode, store_id, store_name,
          source_baseline_import_batch_id, created_by, updated_by, moved_by_user_id
        )
        SELECT
          v_emp_name, v_emp_rec.employee_no, v_emp_rec.employee_no,
          v_acct_name, 'Active',
          v_batch.selected_account_id,
          v_emp_rec.last_name, v_emp_rec.first_name, v_emp_rec.middle_name,
          NULL, false,
          v_emp_rec.position,
          v_emp_rec.deployment_type,
          v_emp_rec.has_penalty,
          v_emp_rec.area,
          v_emp_rec.area_name_snapshot,
          NULL,
          CASE WHEN v_store_cnt = 1 THEN sm.store_id ELSE NULL END,
          CASE WHEN v_store_cnt = 1 THEN r.store_name ELSE NULL END,
          p_batch_id, v_actor, v_actor, v_actor
        FROM (
          SELECT vcode, store_name
            FROM public.plantilla_import_rows
           WHERE batch_id = p_batch_id AND employee_no = v_emp_rec.employee_no
             AND validation_status IN ('valid','flagged')
           ORDER BY row_number LIMIT 1
        ) r
        LEFT JOIN _pib_store_map sm ON sm.vcode = upper(r.vcode)
        RETURNING id INTO v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'insert', NULL, v_uid);

      ELSE
        -- Existing employee: refresh name, presentation fields, import linkage.
        UPDATE public.plantilla
           SET employee_name = v_emp_name,
               last_name     = v_emp_rec.last_name,
               first_name    = v_emp_rec.first_name,
               middle_name   = v_emp_rec.middle_name,
               position      = COALESCE(v_emp_rec.position, public.plantilla.position),
               deployment_type = COALESCE(v_emp_rec.deployment_type, public.plantilla.deployment_type),
               has_penalty   = COALESCE(v_emp_rec.has_penalty, public.plantilla.has_penalty),
               area          = COALESCE(v_emp_rec.area, public.plantilla.area),
               area_name_snapshot = COALESCE(v_emp_rec.area_name_snapshot, public.plantilla.area_name_snapshot),
               account       = v_acct_name,
               account_id    = v_batch.selected_account_id,
               vcode         = NULL,
               store_id      = CASE WHEN v_store_cnt = 1 THEN sm.store_id ELSE NULL END,
               store_name    = CASE WHEN v_store_cnt = 1 THEN v_emp_rec.store_name ELSE NULL END,
               updated_at    = now(),
               updated_by    = v_actor,
               source_baseline_import_batch_id = p_batch_id
          FROM _pib_store_map sm
         WHERE public.plantilla.id = v_plantilla_id
           AND sm.vcode = upper(v_emp_rec.vcode);

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'update', v_old_plant_snap, v_uid);
      END IF;

      -- Link roving group to plantilla master
      IF v_roving_id IS NOT NULL THEN
        UPDATE public.import_roving_groups SET plantilla_id = v_plantilla_id
         WHERE id = v_roving_id;
      END IF;

      -- Write row-level plantilla snapshot
      UPDATE public.plantilla_import_rows
         SET previous_plantilla_snapshot = v_old_plant_snap
       WHERE batch_id = p_batch_id
         AND employee_no = v_emp_rec.employee_no
         AND validation_status IN ('valid','flagged');

      -- Snapshot existing active allocations before superseding (rollback lineage)
      INSERT INTO public.plantilla_import_commit_snapshots
        (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
      SELECT
        p_batch_id, 'allocation', a.id, 'update', to_jsonb(a.*), v_uid
        FROM public.employee_store_allocations a
       WHERE a.employee_no = v_emp_rec.employee_no
         AND a.is_active
         AND a.account_id = v_batch.selected_account_id;

      -- Supersede prior active allocations for this employee in this account
      UPDATE public.employee_store_allocations
         SET is_active = false, effective_end = CURRENT_DATE
       WHERE employee_no = v_emp_rec.employee_no
         AND is_active
         AND account_id = v_batch.selected_account_id;

      -- Create one active allocation row per distinct VCODE for this employee
      FOR v_store_rec IN
        SELECT DISTINCT ON (pir.vcode)
               pir.vcode, sm.store_id,
               pir.store_name, pir.resolved_account_id, pir.resolved_group_id
          FROM public.plantilla_import_rows pir
          LEFT JOIN _pib_store_map sm ON sm.vcode = upper(pir.vcode)
         WHERE pir.batch_id = p_batch_id
           AND pir.employee_no = v_emp_rec.employee_no
           AND pir.validation_status IN ('valid','flagged')
         ORDER BY pir.vcode, pir.row_number
      LOOP
        INSERT INTO public.employee_store_allocations (
          plantilla_id, employee_no, roving_group_id,
          store_id, vcode, store_name,
          account_id, group_id,
          filled_hc, active_store_count,
          effective_start, is_active,
          source_import_batch_id, created_by
        ) VALUES (
          v_plantilla_id, v_emp_rec.employee_no, v_roving_id,
          v_store_rec.store_id, v_store_rec.vcode, v_store_rec.store_name,
          COALESCE(v_store_rec.resolved_account_id, v_batch.selected_account_id),
          COALESCE(v_store_rec.resolved_group_id,   v_batch.selected_group_id),
          v_filled, v_store_cnt,
          CURRENT_DATE, true,
          p_batch_id, v_actor
        );
        v_alloc_done := v_alloc_done + 1;
      END LOOP;

      -- Per-employee audit (OHM2026_0059: APPROVAL enum)
      INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
      VALUES (v_uid, 'plantilla_import', 'APPROVAL', v_plantilla_id,
        jsonb_build_object(
          'employee_no',         v_emp_rec.employee_no,
          'store_count',         v_store_cnt,
          'filled_hc_per_store', v_filled,
          'roving',              (v_roving_id IS NOT NULL),
          'batch_id',            p_batch_id,
          'approver_role',       v_caller_role
        ));
    END LOOP;

    -- ── Finalise batch ──────────────────────────────────────────────────────
    UPDATE public.plantilla_import_batches
       SET status                   = 'approved',
           approved_by              = v_uid,
           approved_at              = now(),
           committed_stores         = v_stores_done,
           committed_employees      = v_employees_done,
           rollback_ready           = true,
           approver_role            = v_caller_role,
           approval_latency_seconds = round(
             extract(epoch from (now() - v_batch.created_at))::numeric, 2
           ),
           updated_at               = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
    VALUES (v_uid, 'plantilla_import_batches', 'APPROVAL', p_batch_id,
      jsonb_build_object(
        'stores',                  v_stores_done,
        'employees',               v_employees_done,
        'allocations',             v_alloc_done,
        'approver_role',           v_caller_role,
        'approval_latency_seconds',
          round(extract(epoch from (now() - v_batch.created_at))::numeric, 2)
      ));

    RETURN jsonb_build_object(
      'batch_id',            p_batch_id,
      'status',              'approved',
      'stores_committed',    v_stores_done,
      'employees_committed', v_employees_done,
      'allocations_created', v_alloc_done
    );

  EXCEPTION WHEN OTHERS THEN
    UPDATE public.plantilla_import_batches
       SET status              = 'commit_failed',
           commit_error_detail = format('[%s] %s', SQLSTATE, SQLERRM),
           updated_at          = now()
     WHERE id = p_batch_id;

    RETURN jsonb_build_object(
      'batch_id', p_batch_id,
      'status',   'commit_failed',
      'error',    format('[%s] %s', SQLSTATE, SQLERRM)
    );
  END;

END$func$;

REVOKE ALL ON FUNCTION public.approve_plantilla_import_batch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_batch(uuid) TO authenticated;

COMMENT ON FUNCTION public.approve_plantilla_import_batch IS
  'Commit RPC for Plantilla Baseline Import (OHM2026_0079 — operational safeguards). '
  'Adds: pg_advisory_xact_lock per batch, expired batch guard (72h inline threshold), '
  'superseded batch detection (newer approved import in same scope), '
  '"Batch already processed." for terminal-state races, '
  'approver_role and approval_latency_seconds audit enrichment. '
  'Carries forward OHM2026_0060 plantilla field hydration and FK fix. '
  'RBAC: Head Admin / Super Admin only.';


-- ============================================================
-- §4  rollback_plantilla_import_batch  (hardened)
-- ============================================================
-- Carries forward all OHM2026_0063 entity rollback logic.
-- Adds:
--   - pg_advisory_xact_lock (same lock namespace as approval — mutually exclusive)
--   - Batch-level superseded scope check (newer approved batch in same group+account)
--   - rollback_role and rollback_latency_seconds populated on success
--   - Enriched rollback audit metadata (role, counts, latency)

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
  v_caller_role text;

  v_plantilla_restored    int := 0;
  v_plantilla_archived    int := 0;
  v_stores_restored       int := 0;
  v_stores_deactivated    int := 0;
  v_allocations_restored  int := 0;
  v_allocations_deactivated int := 0;
  v_roving_groups_archived  int := 0;
BEGIN
  -- ── Auth ─────────────────────────────────────────────────────────────────
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Caller role (for audit enrichment) ───────────────────────────────────
  v_caller_role := public.get_my_role();

  -- ── Advisory lock: serialise concurrent rollback/approval for this batch ──
  -- Uses the same namespace as approve_plantilla_import_batch — prevents
  -- rollback during an in-flight approval transaction and vice versa.
  PERFORM pg_advisory_xact_lock(4207900, hashtext(p_batch_id::text));

  -- ── Lock + state check ───────────────────────────────────────────────────
  SELECT * INTO v_batch
    FROM public.plantilla_import_batches
   WHERE id = p_batch_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotency guard: already rolled back
  IF v_batch.status = 'rolled_back' THEN
    RAISE EXCEPTION 'Batch already processed.'
      USING ERRCODE = 'P0001';
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

  -- ── Entity rollback block ─────────────────────────────────────────────────
  -- Any error rolls back all entity DML and marks rollback_failed.
  BEGIN

    -- ── Batch-level superseded scope check ───────────────────────────────────
    -- Fail closed if a newer approved batch for the same group+account exists.
    -- Rolling back this batch would corrupt the newer batch's foundational state.
    IF EXISTS (
      SELECT 1
        FROM public.plantilla_import_batches newer
       WHERE newer.selected_group_id   = v_batch.selected_group_id
         AND newer.selected_account_id = v_batch.selected_account_id
         AND newer.status IN ('approved', 'rollback_pending')
         AND newer.approved_at > v_batch.approved_at
         AND newer.id <> p_batch_id
    ) THEN
      RAISE EXCEPTION 'ROLLBACK_UNSAFE: a newer approved import batch exists for this scope. Rolling back would corrupt newer batch state.'
        USING ERRCODE = '40001';
    END IF;

    -- ── Entity-level superseded checks (existing OHM2026_0063 guards) ────────
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

    -- ── Batch-created allocations: deactivate only (preserve history) ─────────
    UPDATE public.employee_store_allocations a
       SET is_active = false,
           effective_end = CURRENT_DATE
     WHERE a.source_import_batch_id = p_batch_id
       AND a.is_active;
    GET DIAGNOSTICS v_allocations_deactivated = ROW_COUNT;

    -- ── Batch-updated allocations: restore prior allocation rows ──────────────
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
       SET plantilla_id         = (snap.r).plantilla_id,
           employee_no          = (snap.r).employee_no,
           roving_group_id      = (snap.r).roving_group_id,
           store_id             = (snap.r).store_id,
           vcode                = (snap.r).vcode,
           store_name           = (snap.r).store_name,
           account_id           = (snap.r).account_id,
           group_id             = (snap.r).group_id,
           filled_hc            = (snap.r).filled_hc,
           active_store_count   = (snap.r).active_store_count,
           effective_start      = (snap.r).effective_start,
           effective_end        = (snap.r).effective_end,
           is_active            = (snap.r).is_active,
           source_import_batch_id = (snap.r).source_import_batch_id,
           created_at           = (snap.r).created_at,
           created_by           = (snap.r).created_by
      FROM snap
     WHERE a.id = snap.entity_id;
    GET DIAGNOSTICS v_allocations_restored = ROW_COUNT;

    -- ── Batch-created plantilla rows: soft archive, never hard delete ─────────
    UPDATE public.plantilla p
       SET is_archived    = true,
           archived_at    = now(),
           archived_by    = v_actor,
           archive_reason = v_archive_reason,
           status         = 'Inactive',
           updated_at     = now(),
           updated_by     = v_actor
      FROM public.plantilla_import_commit_snapshots s
     WHERE s.batch_id = p_batch_id
       AND s.entity_type = 'plantilla'
       AND s.action = 'insert'
       AND s.entity_id = p.id
       AND p.source_baseline_import_batch_id = p_batch_id
       AND COALESCE(p.is_archived, false) = false;
    GET DIAGNOSTICS v_plantilla_archived = ROW_COUNT;

    -- ── Batch-updated plantilla rows: restore prior row snapshot ─────────────
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
       SET employee_name              = (snap.r).employee_name,
           employee_no                = (snap.r).employee_no,
           account                    = (snap.r).account,
           status                     = (snap.r).status,
           emploc_no                  = (snap.r).emploc_no,
           vcode                      = (snap.r).vcode,
           position                   = (snap.r).position,
           created_at                 = (snap.r).created_at,
           hr_emploc_id               = (snap.r).hr_emploc_id,
           vacancy_id                 = (snap.r).vacancy_id,
           vacancy_code_snapshot      = (snap.r).vacancy_code_snapshot,
           employee_name_snapshot     = (snap.r).employee_name_snapshot,
           account_id                 = (snap.r).account_id,
           chain_id                   = (snap.r).chain_id,
           store_id                   = (snap.r).store_id,
           province_id                = (snap.r).province_id,
           area_name_snapshot         = (snap.r).area_name_snapshot,
           hrco_user_id_snapshot      = (snap.r).hrco_user_id_snapshot,
           om_user_id_snapshot        = (snap.r).om_user_id_snapshot,
           atl_user_id_snapshot       = (snap.r).atl_user_id_snapshot,
           position_id                = (snap.r).position_id,
           rest_day                   = (snap.r).rest_day,
           resignation_date           = (snap.r).resignation_date,
           remarks                    = (snap.r).remarks,
           moved_by_user_id           = (snap.r).moved_by_user_id,
           created_by                 = (snap.r).created_by,
           updated_at                 = (snap.r).updated_at,
           updated_by                 = (snap.r).updated_by,
           store_name                 = (snap.r).store_name,
           area                       = (snap.r).area,
           rate                       = (snap.r).rate,
           schedule                   = (snap.r).schedule,
           deployment_type            = (snap.r).deployment_type,
           has_penalty                = (snap.r).has_penalty,
           date_hired                 = (snap.r).date_hired,
           coordinator                = (snap.r).coordinator,
           hrco_name                  = (snap.r).hrco_name,
           last_name                  = (snap.r).last_name,
           first_name                 = (snap.r).first_name,
           middle_name                = (snap.r).middle_name,
           date_of_separation         = (snap.r).date_of_separation,
           separation_status          = (snap.r).separation_status,
           tagged_at                  = (snap.r).tagged_at,
           inactive_at                = (snap.r).inactive_at,
           inactive_by                = (snap.r).inactive_by,
           for_deactivation_at        = (snap.r).for_deactivation_at,
           for_deactivation_by        = (snap.r).for_deactivation_by,
           deactivated_at             = (snap.r).deactivated_at,
           deactivated_by             = (snap.r).deactivated_by,
           deactivated_visible_until  = (snap.r).deactivated_visible_until,
           last_mika_synced_at        = (snap.r).last_mika_synced_at,
           last_mika_synced_by        = (snap.r).last_mika_synced_by,
           source_headcount_request_id = (snap.r).source_headcount_request_id,
           is_deleted                 = (snap.r).is_deleted,
           over_headcount             = (snap.r).over_headcount,
           deactivation_reason        = (snap.r).deactivation_reason,
           deletion_requested_at      = (snap.r).deletion_requested_at,
           deletion_requested_by      = (snap.r).deletion_requested_by,
           deletion_reason            = (snap.r).deletion_reason,
           deletion_remarks           = (snap.r).deletion_remarks,
           deletion_approved_at       = (snap.r).deletion_approved_at,
           deletion_approved_by       = (snap.r).deletion_approved_by,
           sss_no                     = (snap.r).sss_no,
           philhealth_no              = (snap.r).philhealth_no,
           pagibig_no                 = (snap.r).pagibig_no,
           atm_no                     = (snap.r).atm_no,
           civil_status               = (snap.r).civil_status,
           date_of_birth              = (snap.r).date_of_birth,
           transferred_from_store_id  = (snap.r).transferred_from_store_id,
           last_transfer_at           = (snap.r).last_transfer_at,
           last_transfer_by           = (snap.r).last_transfer_by,
           inactive_visible_until     = (snap.r).inactive_visible_until,
           is_archived                = (snap.r).is_archived,
           archived_at                = (snap.r).archived_at,
           archived_by                = (snap.r).archived_by,
           archive_reason             = (snap.r).archive_reason,
           restored_at                = (snap.r).restored_at,
           restored_by                = (snap.r).restored_by,
           source_baseline_import_batch_id = (snap.r).source_baseline_import_batch_id,
           roving_assignment_id       = (snap.r).roving_assignment_id,
           is_pool_employee           = (snap.r).is_pool_employee
      FROM snap
     WHERE p.id = snap.entity_id
       AND p.source_baseline_import_batch_id = p_batch_id;
    GET DIAGNOSTICS v_plantilla_restored = ROW_COUNT;

    -- ── Batch-updated stores: restore prior row snapshot ──────────────────────
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
       SET account_id      = (snap.r).account_id,
           store_name      = (snap.r).store_name,
           store_branch    = (snap.r).store_branch,
           area_city       = (snap.r).area_city,
           province        = (snap.r).province,
           is_active       = (snap.r).is_active,
           created_at      = (snap.r).created_at,
           updated_at      = (snap.r).updated_at,
           group_id        = (snap.r).group_id,
           hrco_user_id    = (snap.r).hrco_user_id,
           om_user_id      = (snap.r).om_user_id,
           vcode           = (snap.r).vcode,
           area_province   = (snap.r).area_province,
           type            = (snap.r).type,
           with_penalty    = (snap.r).with_penalty,
           status          = (snap.r).status,
           created_by      = (snap.r).created_by,
           updated_by      = (snap.r).updated_by,
           approved_by     = (snap.r).approved_by,
           approved_at     = (snap.r).approved_at,
           source_import_id = (snap.r).source_import_id,
           employment_type = (snap.r).employment_type
      FROM snap
     WHERE st.id = snap.entity_id
       AND st.source_import_id = p_batch_id;
    GET DIAGNOSTICS v_stores_restored = ROW_COUNT;

    -- ── Batch-created stores: deactivate only when no live plantilla/allocation ─
    UPDATE public.stores st
       SET is_active  = false,
           status     = 'archived',
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

    -- ── Roving groups created by this batch: close if no active allocations ───
    UPDATE public.import_roving_groups g
       SET archived_at = COALESCE(g.archived_at, now()),
           updated_at  = now()
     WHERE g.source_import_batch_id = p_batch_id
       AND NOT EXISTS (
         SELECT 1
           FROM public.employee_store_allocations a
          WHERE a.roving_group_id = g.id
            AND a.is_active
       );
    GET DIAGNOSTICS v_roving_groups_archived = ROW_COUNT;

    -- ── Mark rollback success ─────────────────────────────────────────────────
    UPDATE public.plantilla_import_batches
       SET status                    = 'rolled_back',
           rolled_back_by            = v_uid,
           rolled_back_at            = now(),
           rollback_reason           = v_reason,
           rollback_error_detail     = NULL,
           rollback_role             = v_caller_role,
           rollback_latency_seconds  = round(
             extract(epoch from (now() - v_batch.approved_at))::numeric, 2
           ),
           updated_at                = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, old_data, new_data)
    VALUES (
      v_uid,
      'plantilla_import_batches',
      'UPDATE',
      p_batch_id,
      jsonb_build_object('status', 'approved'),
      jsonb_build_object(
        'status',                   'rolled_back',
        'batch_id',                 p_batch_id,
        'plantilla_restored',       v_plantilla_restored,
        'plantilla_archived',       v_plantilla_archived,
        'stores_restored',          v_stores_restored,
        'stores_deactivated',       v_stores_deactivated,
        'allocations_restored',     v_allocations_restored,
        'allocations_deactivated',  v_allocations_deactivated,
        'roving_groups_archived',   v_roving_groups_archived,
        'rollback_role',            v_caller_role,
        'rollback_latency_seconds', round(
          extract(epoch from (now() - v_batch.approved_at))::numeric, 2
        ),
        'reason',                   v_reason
      )
    );

    RETURN jsonb_build_object(
      'status',                   'rolled_back',
      'batch_id',                 p_batch_id,
      'plantilla_restored',       v_plantilla_restored,
      'plantilla_archived',       v_plantilla_archived,
      'stores_restored',          v_stores_restored,
      'stores_deactivated',       v_stores_deactivated,
      'allocations_restored',     v_allocations_restored,
      'allocations_deactivated',  v_allocations_deactivated,
      'reason',                   v_reason
    );

  EXCEPTION WHEN OTHERS THEN
    UPDATE public.plantilla_import_batches
       SET status                = 'rollback_failed',
           rollback_error_detail = format('[%s] %s', SQLSTATE, SQLERRM),
           rollback_reason       = v_reason,
           updated_at            = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, old_data, new_data)
    VALUES (
      v_uid,
      'plantilla_import_batches',
      'UPDATE',
      p_batch_id,
      jsonb_build_object('status', 'approved'),
      jsonb_build_object(
        'status',        'rollback_failed',
        'batch_id',      p_batch_id,
        'error',         format('[%s] %s', SQLSTATE, SQLERRM),
        'rollback_role', v_caller_role,
        'reason',        v_reason
      )
    );

    RETURN jsonb_build_object(
      'status',   'rollback_failed',
      'batch_id', p_batch_id,
      'error',    format('[%s] %s', SQLSTATE, SQLERRM),
      'reason',   v_reason
    );
  END;
END;
$func$;

REVOKE ALL ON FUNCTION public.rollback_plantilla_import_batch(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rollback_plantilla_import_batch(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.rollback_plantilla_import_batch(uuid, text) IS
  'Rolls back one approved Plantilla Baseline Import batch using commit snapshots. '
  'OHM2026_0079 additions: pg_advisory_xact_lock (prevents concurrent rollback/approval), '
  'batch-level superseded scope check (newer approved batch in same group+account), '
  'rollback idempotency (already rolled_back → Batch already processed.), '
  'rollback_role and rollback_latency_seconds audit enrichment. '
  'Entity rollback is atomic (BEGIN..EXCEPTION). Failures mark rollback_failed. '
  'RBAC: Head Admin / Super Admin only.';


-- ============================================================
-- §5  get_plantilla_import_operational_health
-- ============================================================
-- Lightweight read-only health summary for SA/HA operational monitoring.
-- Returns stale, expired, superseded, failed, and hung batch diagnostics.
-- No DML — STABLE, zero-write.

CREATE OR REPLACE FUNCTION public.get_plantilla_import_operational_health()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_stale_pending        jsonb;
  v_stale_count          int;
  v_expired_recent       jsonb;
  v_expired_count        int;
  v_superseded_pending   jsonb;
  v_superseded_count     int;
  v_commit_failed        jsonb;
  v_commit_failed_count  int;
  v_rollback_failed      jsonb;
  v_rollback_failed_count int;
  v_hung_rollback        jsonb;
  v_hung_rollback_count  int;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- Stale pending batches: pending_approval, not expired, older than 72h
  SELECT
    count(*),
    COALESCE(jsonb_agg(jsonb_build_object(
      'id',           b.id,
      'file_name',    b.file_name,
      'group_id',     b.selected_group_id,
      'account_id',   b.selected_account_id,
      'created_at',   b.created_at,
      'age_hours',    round(extract(epoch from (now() - b.created_at)) / 3600, 1)
    ) ORDER BY b.created_at), '[]'::jsonb)
  INTO v_stale_count, v_stale_pending
  FROM public.plantilla_import_batches b
  WHERE b.status = 'pending_approval'
    AND b.is_expired = false
    AND b.created_at < now() - interval '72 hours';

  -- Recently expired batches (last 30 days)
  SELECT
    count(*),
    COALESCE(jsonb_agg(jsonb_build_object(
      'id',          b.id,
      'file_name',   b.file_name,
      'group_id',    b.selected_group_id,
      'account_id',  b.selected_account_id,
      'created_at',  b.created_at,
      'expired_at',  b.expired_at
    ) ORDER BY b.expired_at DESC), '[]'::jsonb)
  INTO v_expired_count, v_expired_recent
  FROM public.plantilla_import_batches b
  WHERE b.is_expired = true
    AND (b.expired_at IS NULL OR b.expired_at > now() - interval '30 days');

  -- Superseded pending batches: pending_approval batches where a newer approved
  -- batch already exists for the same group+account scope
  SELECT
    count(*),
    COALESCE(jsonb_agg(jsonb_build_object(
      'id',              b.id,
      'file_name',       b.file_name,
      'group_id',        b.selected_group_id,
      'account_id',      b.selected_account_id,
      'created_at',      b.created_at,
      'newer_batch_id',  newer.id,
      'newer_approved_at', newer.approved_at
    ) ORDER BY b.created_at), '[]'::jsonb)
  INTO v_superseded_count, v_superseded_pending
  FROM public.plantilla_import_batches b
  JOIN LATERAL (
    SELECT newer.id, newer.approved_at
      FROM public.plantilla_import_batches newer
     WHERE newer.selected_group_id   = b.selected_group_id
       AND newer.selected_account_id = b.selected_account_id
       AND newer.status = 'approved'
       AND newer.approved_at > b.created_at
       AND newer.id <> b.id
     ORDER BY newer.approved_at DESC
     LIMIT 1
  ) newer ON true
  WHERE b.status = 'pending_approval'
    AND b.is_expired = false;

  -- Recent commit_failed batches (last 14 days)
  SELECT
    count(*),
    COALESCE(jsonb_agg(jsonb_build_object(
      'id',                  b.id,
      'file_name',           b.file_name,
      'group_id',            b.selected_group_id,
      'account_id',          b.selected_account_id,
      'updated_at',          b.updated_at,
      'commit_error_detail', b.commit_error_detail
    ) ORDER BY b.updated_at DESC), '[]'::jsonb)
  INTO v_commit_failed_count, v_commit_failed
  FROM public.plantilla_import_batches b
  WHERE b.status = 'commit_failed'
    AND b.updated_at > now() - interval '14 days';

  -- Recent rollback_failed batches (last 14 days)
  SELECT
    count(*),
    COALESCE(jsonb_agg(jsonb_build_object(
      'id',                    b.id,
      'file_name',             b.file_name,
      'group_id',              b.selected_group_id,
      'account_id',            b.selected_account_id,
      'updated_at',            b.updated_at,
      'rollback_error_detail', b.rollback_error_detail
    ) ORDER BY b.updated_at DESC), '[]'::jsonb)
  INTO v_rollback_failed_count, v_rollback_failed
  FROM public.plantilla_import_batches b
  WHERE b.status = 'rollback_failed'
    AND b.updated_at > now() - interval '14 days';

  -- Hung rollback_pending batches (stuck in rollback_pending > 5 minutes)
  SELECT
    count(*),
    COALESCE(jsonb_agg(jsonb_build_object(
      'id',         b.id,
      'file_name',  b.file_name,
      'group_id',   b.selected_group_id,
      'account_id', b.selected_account_id,
      'updated_at', b.updated_at,
      'stuck_minutes', round(extract(epoch from (now() - b.updated_at)) / 60, 1)
    ) ORDER BY b.updated_at), '[]'::jsonb)
  INTO v_hung_rollback_count, v_hung_rollback
  FROM public.plantilla_import_batches b
  WHERE b.status = 'rollback_pending'
    AND b.updated_at < now() - interval '5 minutes';

  RETURN jsonb_build_object(
    'generated_at',              now(),
    'stale_pending_count',       v_stale_count,
    'stale_pending_batches',     v_stale_pending,
    'expired_count',             v_expired_count,
    'expired_batches',           v_expired_recent,
    'superseded_pending_count',  v_superseded_count,
    'superseded_pending_batches', v_superseded_pending,
    'commit_failed_count',       v_commit_failed_count,
    'commit_failed_batches',     v_commit_failed,
    'rollback_failed_count',     v_rollback_failed_count,
    'rollback_failed_batches',   v_rollback_failed,
    'hung_rollback_count',       v_hung_rollback_count,
    'hung_rollback_batches',     v_hung_rollback
  );
END$func$;

REVOKE ALL ON FUNCTION public.get_plantilla_import_operational_health() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_import_operational_health() TO authenticated;

COMMENT ON FUNCTION public.get_plantilla_import_operational_health() IS
  'Lightweight read-only operational health summary for Import Plantilla batch lifecycle. '
  'Returns stale/expired/superseded pending batches, hung rollback_pending, recent '
  'commit_failed and rollback_failed counts. Zero DML — safe to poll. '
  'RBAC: Head Admin / Super Admin only.';
