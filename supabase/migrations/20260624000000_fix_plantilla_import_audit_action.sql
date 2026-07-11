-- ============================================================
-- OHM2026_0059 — Fix Plantilla Import Audit Action Enum Values
-- Migration:  20260624000000_fix_plantilla_import_audit_action.sql
-- Depends on: 20260622000000_fix_plantilla_import_commit_fk_order.sql
-- ============================================================
-- Root Cause
--   Two audit_logs inserts in the import approval pipeline used
--   enum values not present in public.audit_action:
--
--   1. approve_plantilla_import_batch (per-employee loop):
--        action = 'COMMIT'   → not a valid audit_action value
--      Fix: replace with 'APPROVAL' (import approval is an approval action)
--
--   2. reject_plantilla_import_batch:
--        action = 'REJECTION' → not a valid audit_action value
--      Fix: replace with 'UPDATE' (status transition update)
--
--   Valid audit_action enum values:
--     INSERT, UPDATE, SOFT_DELETE, APPROVAL, BACKOUT,
--     START_ACTING_SESSION, STOP_ACTING_SESSION,
--     ACTIVATE_USER, DEACTIVATE_USER, CREATE_USER, UPDATE_USER_ROLE,
--     ARCHIVE_USER, RESET_PASSWORD_REQUEST, UPDATE_AVATAR,
--     UPDATE_MOBILE, CHANGE_PASSWORD, UPDATE_SETTINGS
--
-- Sections
--   §1  approve_plantilla_import_batch  (COMMIT → APPROVAL)
--   §2  reject_plantilla_import_batch   (REJECTION → UPDATE)
--   §3  get_plantilla_import_batches    (scope/uploader display fields)
--
-- Replay safety
--   CREATE OR REPLACE — idempotent on re-apply.
--   All other logic is identical to the previous versions.
--   No DDL changes to tables, indexes, or constraints.
--
-- Failed batch
--   7b685cf5-c500-4665-bac7-1d65cee4ca10 — remains commit_failed.
--   Do NOT manually repair.  Create a new import batch for retest.
--
-- Validation checklist (run after applying)
--   V1  Enum values in use:
--         SELECT unnest(enum_range(null::public.audit_action))::text;
--   V2  Failed batch unchanged:
--         SELECT status, commit_error_detail
--           FROM plantilla_import_batches
--          WHERE id = '7b685cf5-c500-4665-bac7-1d65cee4ca10';
--   V3  Recent batches:
--         SELECT file_name, status
--           FROM plantilla_import_batches
--          ORDER BY created_at DESC LIMIT 10;
--   V4  Approve new batch → status = approved, audit_logs has action = 'APPROVAL'
--   V5  Reject new batch  → status = rejected, audit_logs has action = 'UPDATE'
-- ============================================================


-- ============================================================
-- §1  approve_plantilla_import_batch  (COMMIT → APPROVAL)
-- ============================================================
-- Identical to OHM2026_0057 version except:
--   per-employee audit insert: action 'COMMIT' replaced with 'APPROVAL'

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

        -- Commit snapshot: new store
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

        -- Commit snapshot: store before update (rollback restore target)
        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_existing_store_id, 'update', v_old_store_snap, v_uid);
      END IF;

      -- Write row-level rollback snapshot
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
        -- plantilla.vcode is intentionally NULL for baseline import rows:
        --   fk_plantilla_vcode references vacancies(vcode), and import VCODEs
        --   do not have corresponding vacancy rows (baseline import bypasses
        --   the normal vacancy → hr_emploc → plantilla hire path).
        --   The store reference is fully captured by store_id.
        --   VCODE lineage is preserved in employee_store_allocations.vcode.
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
          -- vcode is always NULL for import rows: fk_plantilla_vcode → vacancies(vcode)
          NULL,
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

        -- Commit snapshot: new plantilla insert (no previous state)
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

        -- Commit snapshot: plantilla before update
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

      -- FIX OHM2026_0059: 'COMMIT' → 'APPROVAL' (COMMIT is not a valid audit_action enum value)
      INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
      VALUES (v_uid, 'plantilla_import', 'APPROVAL', v_plantilla_id,
        jsonb_build_object(
          'employee_no',         v_emp_rec.employee_no,
          'store_count',         v_store_cnt,
          'filled_hc_per_store', v_filled,
          'roving',              (v_roving_id IS NOT NULL),
          'batch_id',            p_batch_id
        ));
    END LOOP;

    -- ── Finalise batch ──────────────────────────────────────────────────────
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
  'Commit RPC for Plantilla Baseline Import (OHM2026_0059 — audit enum fix). '
  'Per-employee audit insert uses APPROVAL (was COMMIT, which is not a valid audit_action). '
  'All other logic identical to OHM2026_0057 (FK fix + VCODE resolution guard). '
  'RBAC: Head Admin / Super Admin only.';


-- ============================================================
-- §2  reject_plantilla_import_batch  (REJECTION → UPDATE)
-- ============================================================
-- Identical to OHM2026_0053 version except:
--   audit insert: action 'REJECTION' replaced with 'UPDATE'
--   (REJECTION is not a valid audit_action enum value; this is a status-transition UPDATE)

CREATE OR REPLACE FUNCTION public.reject_plantilla_import_batch(
  p_batch_id uuid,
  p_reason   text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid   uuid := auth.uid();
  v_batch public.plantilla_import_batches%ROWTYPE;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: rejection reason required'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_batch.status NOT IN ('pending_approval','validation_failed','draft_uploaded') THEN
    RAISE EXCEPTION 'INVALID_STATE: cannot reject batch in % state', v_batch.status
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.plantilla_import_batches
     SET status           = 'rejected',
         rejected_by      = v_uid,
         rejected_at      = now(),
         rejection_reason = p_reason,
         updated_at       = now()
   WHERE id = p_batch_id;

  -- FIX OHM2026_0059: 'REJECTION' → 'UPDATE' (REJECTION is not a valid audit_action enum value)
  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'plantilla_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object('reason', p_reason, 'new_status', 'rejected'));

  RETURN jsonb_build_object('batch_id', p_batch_id, 'status', 'rejected');
END$func$;

REVOKE ALL ON FUNCTION public.reject_plantilla_import_batch(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_plantilla_import_batch(uuid,text) TO authenticated;

COMMENT ON FUNCTION public.reject_plantilla_import_batch IS
  'Reject RPC for Plantilla Baseline Import (OHM2026_0059 — audit enum fix). '
  'Audit insert uses UPDATE (was REJECTION, which is not a valid audit_action). '
  'All other logic identical to OHM2026_0053. '
  'RBAC: Head Admin / Super Admin only.';


-- ============================================================
-- §3  get_plantilla_import_batches  (scope/uploader display fields)
-- ============================================================
-- Replaces raw SETOF plantilla_import_batches with an enriched row contract.
-- Scope enforcement is unchanged: full-access users can see all batches;
-- other authenticated users can only see their own uploads.

DROP FUNCTION IF EXISTS public.get_plantilla_import_batches(text);

CREATE OR REPLACE FUNCTION public.get_plantilla_import_batches(
  p_status text DEFAULT NULL
)
RETURNS TABLE (
  id                         uuid,
  file_name                  text,
  uploaded_by                uuid,
  uploader_name              text,
  uploaded_by_name           text,
  uploaded_role              text,
  selected_group_id          uuid,
  selected_account_id        uuid,
  group_name                 text,
  account_name               text,
  status                     text,
  total_rows                 integer,
  valid_rows                 integer,
  flagged_rows               integer,
  skipped_rows               integer,
  blocked_rows               integer,
  roving_detected            integer,
  new_stores_count           integer,
  existing_stores_count      integer,
  existing_employees_count   integer,
  cross_account_conflicts    integer,
  cross_group_conflicts      integer,
  over_20_store_warnings     integer,
  missing_from_upload_count  integer,
  error_summary              jsonb,
  commit_error_detail        text,
  approved_by                uuid,
  approved_at                timestamptz,
  committed_stores           integer,
  committed_employees        integer,
  rollback_ready             boolean,
  rejected_by                uuid,
  rejected_at                timestamptz,
  rejection_reason           text,
  created_at                 timestamptz,
  updated_at                 timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
  SELECT
    b.id,
    b.file_name,
    b.uploaded_by,
    up.full_name AS uploader_name,
    up.full_name AS uploaded_by_name,
    b.uploaded_role,
    b.selected_group_id,
    b.selected_account_id,
    g.group_name,
    a.account_name,
    b.status,
    b.total_rows,
    b.valid_rows,
    b.flagged_rows,
    b.skipped_rows,
    b.blocked_rows,
    b.roving_detected,
    b.new_stores_count,
    b.existing_stores_count,
    b.existing_employees_count,
    b.cross_account_conflicts,
    b.cross_group_conflicts,
    b.over_20_store_warnings,
    b.missing_from_upload_count,
    b.error_summary,
    b.commit_error_detail,
    b.approved_by,
    b.approved_at,
    b.committed_stores,
    b.committed_employees,
    b.rollback_ready,
    b.rejected_by,
    b.rejected_at,
    b.rejection_reason,
    b.created_at,
    b.updated_at
    FROM public.plantilla_import_batches b
    LEFT JOIN public.groups g
      ON g.id = b.selected_group_id
    LEFT JOIN public.accounts a
      ON a.id = b.selected_account_id
    LEFT JOIN LATERAL (
      SELECT up.full_name
        FROM public.users_profile up
       WHERE up.auth_user_id = b.uploaded_by OR up.id = b.uploaded_by
       ORDER BY CASE WHEN up.auth_user_id = b.uploaded_by THEN 0 ELSE 1 END
       LIMIT 1
    ) up ON true
   WHERE (public.i_have_full_access() OR b.uploaded_by = auth.uid())
     AND (p_status IS NULL OR b.status = p_status)
   ORDER BY b.created_at DESC;
$func$;

REVOKE ALL ON FUNCTION public.get_plantilla_import_batches(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_import_batches(text) TO authenticated;

COMMENT ON FUNCTION public.get_plantilla_import_batches(text) IS
  'List Plantilla Baseline Import batches visible to the caller, enriched with '
  'group_name, account_name, and uploader display name for Review Import and '
  'Import History scope display. Scope enforcement is unchanged.';
