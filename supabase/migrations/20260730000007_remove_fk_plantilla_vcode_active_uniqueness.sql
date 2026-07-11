-- ============================================================
-- OHM2026_1144 — Remove fk_plantilla_vcode and formalize permanent VCODE lifecycle
-- Migration:  20260730000007_remove_fk_plantilla_vcode_active_uniqueness.sql
-- Depends on: 20260706000000_patch_import_optional_employee_fields.sql
--             20260622000000_fix_plantilla_import_commit_fk_order.sql
-- ============================================================
-- Architectural intent
--   VCODE is the permanent manpower-slot lifecycle ID. Workflow ownership
--   no longer belongs to a single side of the Vacancy ↔ Plantilla pair:
--
--     • Vacancy  = open / pipeline slot state
--     • Plantilla = occupied / active slot state
--
--   Both reference the same VCODE over its lifetime. The same VCODE moves
--   back to Vacancy whenever the active employee resigns / deactivates,
--   and resumes its lifecycle from there.
--
--   The Import Plantilla migration tool brings in active employees whose
--   VCODEs never existed in Vacancy. Those imported VCODEs must still
--   participate in the lifecycle, including a future resign → reopen-as-
--   vacancy transition. A hard FK from plantilla.vcode → vacancies.vcode
--   forbids that and forces plantilla.vcode = NULL for every import row,
--   which loses the permanent VCODE on the master record.
--
--   This migration removes the FK and enforces VCODE single-occupancy at
--   the plantilla layer via a partial unique index (active occupied rows
--   only). Workflow lineage (Vacancy → HR Emploc → Plantilla) continues
--   to be enforced inside move_to_plantilla and related RPCs, not by an
--   FK between plantilla and vacancies.
--
-- Changes
--   §1  Drop FK fk_plantilla_vcode (plantilla.vcode → vacancies.vcode)
--   §2  Add partial unique index uq_plantilla_vcode_active_occupied
--         — at most one ACTIVE occupied plantilla row per VCODE
--         — excludes deleted rows, pool/open-slot rows, and inactive statuses
--   §3  CREATE OR REPLACE approve_plantilla_import_batch
--         — single-store import rows now persist plantilla.vcode = r.vcode
--           (roving employees keep plantilla.vcode = NULL; their VCODE
--           lineage continues to live in employee_store_allocations)
--         — human-readable error remap on 23505 from the new index
--   §4  Comments on plantilla.vcode and the new index documenting
--       permanent VCODE lifecycle ownership.
--
-- Non-goals (explicitly out of scope)
--   • Do NOT modify any applied migration
--   • Do NOT drop plantilla.vcode
--   • Do NOT auto-create vacancy rows from Import Plantilla
--   • Do NOT touch any Vacancy table FK or constraint
--   • Do NOT change resign / separation / reopen / transfer / move_to_plantilla
--     workflow logic
--
-- Replay safety
--   §1  IF EXISTS guard
--   §2  CREATE UNIQUE INDEX IF NOT EXISTS
--   §3  CREATE OR REPLACE
--
-- Acceptance
--   A1  fk_plantilla_vcode no longer exists in pg_constraint
--   A2  Import Plantilla commits active employees with VCODEs that have
--       no vacancy row; plantilla.vcode is persisted for single-store rows
--   A3  Inserting a second ACTIVE occupied plantilla row sharing the same
--       VCODE raises 23505 against uq_plantilla_vcode_active_occupied;
--       Import Plantilla surfaces a human-readable error instead of the
--       generic FK-violation message
--   A4  Pool employees (is_pool_employee = true) are exempt — multiple
--       pool/open-slot rows may share a VCODE
--   A5  Deactivating/resigning an active plantilla row frees the VCODE
--       so a fresh Vacancy row may be reopened against it later
--   A6  No vacancy module FK / constraint is altered
-- ============================================================


-- ============================================================
-- §1  Drop fk_plantilla_vcode
-- ============================================================

ALTER TABLE public.plantilla
  DROP CONSTRAINT IF EXISTS fk_plantilla_vcode;


-- ============================================================
-- §2  Active-occupancy uniqueness on plantilla.vcode
-- ============================================================
-- Partial unique index — only ACTIVE occupied employee rows participate.
-- Excludes:
--   • soft-deleted rows  (is_deleted = true)
--   • pool / open-slot rows (is_pool_employee = true) — Plantilla
--     Vacancy Tab models open slots in the same table and must not
--     contend for occupancy uniqueness
--   • non-active statuses (Inactive / Deactivated / Resigned / Transferred)
--   • NULL vcode rows — roving master records carry vcode = NULL;
--     their per-store occupancy is tracked in employee_store_allocations
--
-- Matches the active-set already used by uq_plantilla_employee_no_active.

CREATE UNIQUE INDEX IF NOT EXISTS uq_plantilla_vcode_active_occupied
  ON public.plantilla (vcode)
  WHERE (
    vcode IS NOT NULL
    AND is_deleted = false
    AND is_pool_employee = false
    AND status IN ('Active', 'For Deactivation', 'On Leave')
  );

COMMENT ON INDEX public.uq_plantilla_vcode_active_occupied IS
  'OHM2026_1144 — At most one ACTIVE occupied plantilla row per VCODE. '
  'Replaces fk_plantilla_vcode as the integrity guard on VCODE ownership. '
  'Excludes soft-deleted rows, pool/open-slot rows (is_pool_employee), and '
  'inactive statuses, so a VCODE freed by resignation/deactivation can be '
  'reopened as a Vacancy and later re-occupied by a new active employee.';

COMMENT ON COLUMN public.plantilla.vcode IS
  'Permanent manpower-slot lifecycle ID. Same VCODE is shared with the '
  'vacancies table over the slot lifetime; ownership is no longer enforced '
  'by FK. Active-row uniqueness is enforced by uq_plantilla_vcode_active_occupied. '
  'NULL for roving master rows (per-store lineage lives in employee_store_allocations).';


-- ============================================================
-- §3  approve_plantilla_import_batch — persist plantilla.vcode for
--     single-store imports; humanise 23505 on the new unique index
-- ============================================================

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

  -- Phase A locals
  v_srow               record;
  v_existing_store_id  uuid;
  v_new_store_id       uuid;
  v_old_store_snap     jsonb;
  v_pen_bool           boolean;
  v_emp_type_norm      text;
  v_stores_done        int := 0;

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

  -- Humanised error
  v_err_state text;
  v_err_msg   text;
  v_err_out   text;
BEGIN
  -- ── Auth ─────────────────────────────────────────────────────────────────
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Lock + state check ───────────────────────────────────────────────────
  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)',
      v_batch.status USING ERRCODE = '22023';
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

      SELECT to_jsonb(s.*) INTO v_old_store_snap
        FROM public.stores s
       WHERE upper(s.vcode) = upper(v_srow.vcode) AND s.status = 'active'
       ORDER BY s.created_at LIMIT 1;

      IF v_old_store_snap IS NULL THEN
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
      SELECT employee_no,
             count(DISTINCT vcode)        AS store_count,
             (array_agg(last_name))[1]    AS last_name,
             (array_agg(first_name))[1]   AS first_name,
             (array_agg(middle_name))[1]  AS middle_name
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid','flagged')
         AND employee_no IS NOT NULL
       GROUP BY employee_no
    LOOP
      v_employees_done := v_employees_done + 1;
      v_store_cnt := v_emp_rec.store_count;
      v_filled    := round(1.0 / GREATEST(v_store_cnt, 1), 4);
      v_emp_name  := v_emp_rec.last_name || ', ' || v_emp_rec.first_name
                     || COALESCE(' ' || v_emp_rec.middle_name, '');

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

      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no
         AND is_deleted = false
         AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
       LIMIT 1;

      SELECT to_jsonb(p.*) INTO v_old_plant_snap
        FROM public.plantilla p WHERE id = v_plantilla_id;

      IF v_plantilla_id IS NULL THEN
        -- New employee: insert plantilla master.
        -- OHM2026_1144: plantilla.vcode is now persisted for single-store
        -- import rows (the FK to vacancies has been dropped; VCODE is the
        -- permanent slot lifecycle ID, shared with vacancies over time).
        -- Roving employees keep vcode = NULL; their per-VCODE lineage lives
        -- in employee_store_allocations.
        INSERT INTO public.plantilla (
          employee_name, employee_no, emploc_no, account, status,
          account_id, last_name, first_name, middle_name,
          roving_assignment_id, is_pool_employee,
          vcode, store_id, store_name,
          source_baseline_import_batch_id, created_by, moved_by_user_id
        )
        SELECT
          v_emp_name, v_emp_rec.employee_no, v_emp_rec.employee_no,
          v_acct_name, 'Active',
          v_batch.selected_account_id,
          v_emp_rec.last_name, v_emp_rec.first_name, v_emp_rec.middle_name,
          NULL, false,
          CASE WHEN v_store_cnt = 1 THEN r.vcode    ELSE NULL END,
          CASE WHEN v_store_cnt = 1 THEN sm.store_id ELSE NULL END,
          CASE WHEN v_store_cnt = 1 THEN r.store_name ELSE NULL END,
          p_batch_id, v_actor, v_actor
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
        -- Existing employee: refresh name + import linkage only.
        UPDATE public.plantilla
           SET employee_name = v_emp_name,
               last_name     = v_emp_rec.last_name,
               first_name    = v_emp_rec.first_name,
               middle_name   = v_emp_rec.middle_name,
               updated_at    = now(),
               source_baseline_import_batch_id = p_batch_id
         WHERE id = v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'update', v_old_plant_snap, v_uid);
      END IF;

      IF v_roving_id IS NOT NULL THEN
        UPDATE public.import_roving_groups SET plantilla_id = v_plantilla_id
         WHERE id = v_roving_id;
      END IF;

      UPDATE public.plantilla_import_rows
         SET previous_plantilla_snapshot = v_old_plant_snap
       WHERE batch_id = p_batch_id
         AND employee_no = v_emp_rec.employee_no
         AND validation_status IN ('valid','flagged');

      INSERT INTO public.plantilla_import_commit_snapshots
        (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
      SELECT
        p_batch_id, 'allocation', a.id, 'update', to_jsonb(a.*), v_uid
        FROM public.employee_store_allocations a
       WHERE a.employee_no = v_emp_rec.employee_no
         AND a.is_active
         AND a.account_id = v_batch.selected_account_id;

      UPDATE public.employee_store_allocations
         SET is_active = false, effective_end = CURRENT_DATE
       WHERE employee_no = v_emp_rec.employee_no
         AND is_active
         AND account_id = v_batch.selected_account_id;

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

      INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
      VALUES (v_uid, 'plantilla_import', 'COMMIT', v_plantilla_id,
        jsonb_build_object(
          'employee_no',         v_emp_rec.employee_no,
          'store_count',         v_store_cnt,
          'filled_hc_per_store', v_filled,
          'roving',              (v_roving_id IS NOT NULL),
          'batch_id',            p_batch_id
        ));
    END LOOP;

    UPDATE public.plantilla_import_batches
       SET status             = 'approved',
           approved_by        = v_uid,
           approved_at        = now(),
           committed_stores   = v_stores_done,
           committed_employees= v_employees_done,
           rollback_ready     = true,
           updated_at         = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
    VALUES (v_uid, 'plantilla_import_batches', 'APPROVAL', p_batch_id,
      jsonb_build_object(
        'stores',      v_stores_done,
        'employees',   v_employees_done,
        'allocations', v_alloc_done
      ));

    RETURN jsonb_build_object(
      'batch_id',            p_batch_id,
      'status',              'approved',
      'stores_committed',    v_stores_done,
      'employees_committed', v_employees_done,
      'allocations_created', v_alloc_done
    );

  EXCEPTION WHEN OTHERS THEN
    -- Translate the new active-occupancy unique index into a
    -- human-readable batch error. All Phase A + B DML is rolled back.
    GET STACKED DIAGNOSTICS
      v_err_state = RETURNED_SQLSTATE,
      v_err_msg   = MESSAGE_TEXT;

    IF v_err_state = '23505'
       AND position('uq_plantilla_vcode_active_occupied' IN COALESCE(v_err_msg,'')) > 0
    THEN
      v_err_out := 'VCODE_ALREADY_OCCUPIED: a VCODE in this batch is already held '
                || 'by another active employee in plantilla — only one active '
                || 'occupancy per VCODE is allowed';
    ELSE
      v_err_out := format('[%s] %s', v_err_state, v_err_msg);
    END IF;

    UPDATE public.plantilla_import_batches
       SET status              = 'commit_failed',
           commit_error_detail = v_err_out,
           updated_at          = now()
     WHERE id = p_batch_id;

    RETURN jsonb_build_object(
      'batch_id', p_batch_id,
      'status',   'commit_failed',
      'error',    v_err_out
    );
  END;

END$func$;

REVOKE ALL ON FUNCTION public.approve_plantilla_import_batch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_batch(uuid) TO authenticated;

COMMENT ON FUNCTION public.approve_plantilla_import_batch IS
  'Commit RPC for Plantilla Baseline Import (OHM2026_1144). '
  'plantilla.vcode is now persisted for single-store import rows — the FK '
  'fk_plantilla_vcode → vacancies(vcode) has been removed; VCODE is the '
  'permanent slot lifecycle ID shared with the vacancies table. Roving '
  'employees keep vcode = NULL on the plantilla master row (per-VCODE '
  'lineage in employee_store_allocations). Active-occupancy uniqueness is '
  'enforced by uq_plantilla_vcode_active_occupied; on 23505 the batch '
  'commit_error_detail surfaces VCODE_ALREADY_OCCUPIED instead of the raw '
  'index violation. RBAC: Head Admin / Super Admin only.';
