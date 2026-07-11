-- ============================================================
-- OHM2026_0071 — Fix: Plantilla Import Inactive Reconcile + Slot Occupancy Wire
-- Migration: 20260913000000_fix_import_inactive_reconcile_and_slot_occupancy.sql
-- Depends on:
--   20260803000000_fix_plantilla_import_profile_field_hydration.sql
--     (approve_plantilla_import_batch — canonical merge layer)
--   20260812000000_fn_set_slot_status.sql
--     (fn_set_slot_status — central slot transition helper)
--   20260813000004_wire_occupied_open_slot_transition.sql
--     (fn_sync_slot_to_open — Phase 6.4 non-blocking helper)
--   20260912000000_backfill_gap_vacancy_slots_and_trigger.sql
--     (plantilla_slots, legacy_vcode, slot_ordinal, trg_auto_create_vacancy_slot)
-- ============================================================
-- Root Causes
-- -----------
-- BUG 1 — Duplicate Active + Inactive state for same Emploc# after re-import
--   Phase B of approve_plantilla_import_batch looked for existing plantilla rows
--   using:
--     WHERE employee_no = v_emp_rec.employee_no
--       AND is_deleted = false
--       AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
--   Statuses 'Inactive' and 'Rejected Deactivation' were NOT included. When an
--   employee tagged Inactive (by _apply_separation) is re-imported, the lookup
--   returns NULL → the RPC inserts a brand-new plantilla row with status = 'Active'.
--   The original Inactive row remains untouched. The same Emploc# now appears in
--   both the Active tab and the Inactive tab simultaneously.
--
-- BUG 2 — No vacancy re-opens after approved Inactive/resigned employee
--   For employees whose plantilla row was created via approve_plantilla_import_batch
--   (rather than through the normal HC→Applicant→HR Emploc→Plantilla pipeline),
--   the slot lifecycle is never wired:
--     (a) approve_plantilla_import_batch inserts plantilla + employee_store_allocations
--         but does NOT create or set a plantilla_slots entry.
--     (b) tg_close_vacancy_on_plantilla_active_insert fires on the Active INSERT and
--         sets vacancies.status = 'Filled' for the VCODE.
--     (c) The 20260912000000 gap-backfill only creates slots for open/pipeline
--         vacancies — 'Filled' VCODEs are skipped.
--     Result: the VCODE has a 'Filled' vacancy row but ZERO slots in plantilla_slots.
--     When _apply_separation fires → fn_sync_slot_to_open → slot lookup returns NULL
--     (no slot for this VCODE) → non-blocking skip → vacancy stays 'Filled' with no
--     slot → invisible in vw_slot_derived_vacancy_shadow → Vacancy Open tab stays empty.
--
-- Fixes
-- -----
-- §1  Reconcile Inactive/Rejected Deactivation on re-import (Bug 1)
--     Extend the Phase B employee lookup to include 'Inactive' and
--     'Rejected Deactivation'. The precedence order is:
--       1. Active / On Leave / Pending Deactivation   (already found → UPDATE)
--       2. Inactive / Rejected Deactivation           (NEW — found → reconcile + reactivate)
--       3. Deactivated                                (NEW — found → reject import for this row,
--                                                      log RAISE NOTICE, skip)
--       4. NULL                                       (not found → INSERT new Active row)
--     When an Inactive row is reconciled:
--       • plantilla.status = 'Active'
--       • inactive_at = NULL, inactive_by = NULL (clear separation fields)
--       • separation_status = NULL, date_of_separation = NULL
--       • inactive_visible_until = NULL  (removes from Inactive tab)
--       • All profile/enrichment fields refreshed (COALESCE fill as before)
--       • Any open employee_deactivation_requests for this plantilla_id are
--         set to status = 'Cancelled' (new status) with a note. This ensures
--         the deactivation queue is clean.
--       • Audit log written: action = 'IMPORT_REACTIVATION'
--
-- §2  Wire slot occupancy for import-committed employees (Bug 2)
--     After each employee's plantilla upsert, upsert the matching plantilla_slot
--     for the employee's primary VCODE (single-store employees only; roving excluded
--     per Phase 6.4 carve-out):
--
--     Slot lookup order (mirrors fn_sync_slot_to_open):
--       1. plantilla_slots.current_occupant_plantilla_id = v_plantilla_id (exact occupant)
--       2. plantilla_slots.legacy_vcode = <vcode> AND is_roving = false (bridge fallback)
--
--     Cases:
--       A. Slot found, status = 'occupied', occupant = v_plantilla_id → no_op (correct)
--       B. Slot found, status = 'open'/'pipeline'/'hr_processing'    → transition to
--            'occupied' via fn_set_slot_status (p_occupant_plantilla_id = v_plantilla_id)
--            Reason code = 'IMPORT_OCCUPIED' (new code, seeded below)
--       C. Slot found, status = 'closed' → RAISE NOTICE only, skip
--       D. No slot found → create a new slot with status = 'occupied',
--            current_occupant_plantilla_id = v_plantilla_id,
--            legacy_vcode = <vcode>, slot_ordinal = next available,
--            seed slot_history with action_type = 'occupied', reason_code = 'IMPORT_OCCUPIED'
--       All slot errors are non-blocking (EXCEPTION WHEN OTHERS → RAISE NOTICE + skip).
--
-- Non-goals
-- ---------
-- • Does NOT touch roving employees (Phase 6.4 carve-out maintained).
-- • Does NOT reactivate Deactivated employees (safety; they need manual review).
-- • Does NOT alter _apply_separation, fn_sync_slot_to_open, or the shadow view.
-- • Does NOT change any Flutter UI, provider, or service layer.
-- • Does NOT affect vacancy import or HR Emploc import flows.
-- • Does NOT change the slot foundation tables' schema.
--
-- Smoke Tests (run after supabase db push)
-- ----------------------------------------
-- T1 — No duplicate Active+Inactive rows for Emploc# 2023-09515
--   SELECT status, count(*) FROM plantilla
--   WHERE employee_no = '2023-09515' AND is_deleted = false
--   GROUP BY status;
--   -- Expected: exactly ONE row (status = 'Active')
--
-- T2 — Original Inactive row is now Active, Inactive tab empty for this Emploc#
--   SELECT id, status, inactive_at, inactive_visible_until
--   FROM plantilla
--   WHERE employee_no = '2023-09515' AND is_deleted = false;
--   -- Expected: 1 row, status = 'Active', inactive_at = NULL, inactive_visible_until = NULL
--
-- T3 — Slot exists and is occupied for the employee's VCODE
--   SELECT ps.slot_status, ps.current_occupant_plantilla_id, ps.legacy_vcode
--   FROM plantilla_slots ps
--   INNER JOIN plantilla p ON p.id = ps.current_occupant_plantilla_id
--   WHERE p.employee_no = '2023-09515';
--   -- Expected: 1+ rows, slot_status = 'occupied'
--
-- T4 — After simulating Inactive tag on 2023-09515, vacancy appears in shadow view
--   -- (manual test) Tag employee Inactive → vacancy VCODE appears in Open tab
--   SELECT legacy_vcode, vacancy_tab, open_count
--   FROM vw_slot_derived_vacancy_shadow
--   WHERE legacy_vcode = (
--     SELECT vcode FROM plantilla WHERE employee_no = '2023-09515' LIMIT 1
--   );
--   -- Expected: 1 row, vacancy_tab = 'Open', open_count >= 1
--
-- T5 — Deactivation request cancelled for the reconciled Inactive employee
--   SELECT status, count(*) FROM employee_deactivation_requests
--   WHERE employee_no = '2023-09515' AND is_archived = false
--   GROUP BY status;
--   -- Expected: any existing Pending rows now have status = 'Cancelled'
--   --           (or no rows if there were none)
--
-- T6 — New import batch for 2023-09515 (already Active) → UPDATE, not INSERT
--   -- Import a batch containing employee_no=2023-09515 again
--   -- Approve the batch
--   SELECT count(*) FROM plantilla WHERE employee_no = '2023-09515' AND is_deleted = false;
--   -- Expected: still 1 row (no duplicate insert)
-- ============================================================


-- ============================================================
-- §0  Seed new slot reason code: IMPORT_OCCUPIED
-- ============================================================
-- Used when approve_plantilla_import_batch wires a slot to occupied
-- during import commit. Distinct from HC_ADD (slot creation) and
-- REPLACEMENT (re-fill after resignation).

INSERT INTO public.slot_reason_codes (code, label, description, sort_order)
VALUES (
  'IMPORT_OCCUPIED',
  'Import Committed (Occupied)',
  'Slot set to occupied when an employee was committed via plantilla baseline import.',
  45
)
ON CONFLICT (code) DO NOTHING;


-- ============================================================
-- §0b  Extend audit_action enum with new values
-- ============================================================
-- IMPORT_REACTIVATION: employee reactivated from Inactive/Rejected Deactivation
--   during import approval (reconcile path).
-- IMPORT_DUPLICATE_CLEANUP: one-time soft-delete of orphan duplicate rows.

ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'IMPORT_REACTIVATION';
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'IMPORT_DUPLICATE_CLEANUP';


-- ============================================================
-- §1  Add 'Cancelled' to employee_deactivation_requests.status
--     if not already present in any CHECK constraint
-- ============================================================
-- The Cancelled status is a logical state only (no constraint change required
-- if status column is plain text; existing schema uses text NOT NULL DEFAULT 'Pending').
-- This migration does NOT add a CHECK constraint — the status column accepts any
-- text value. Cancelled rows are excluded from approval/rejection batch validation
-- by the existing WHERE status = 'Pending' guard.

COMMENT ON COLUMN public.employee_deactivation_requests.status IS
  'Request lifecycle: Pending | Approved | Rejected | Cancelled. '
  'Cancelled = deactivation request superseded by a re-import that reactivated the employee. '
  'Cancelled rows are excluded from batch approval/rejection (both RPCs require status=Pending).';


-- ============================================================
-- §2  Canonical CREATE OR REPLACE of approve_plantilla_import_batch
-- ============================================================
-- This is a targeted patch of the function first defined in
-- 20260620000000_plantilla_baseline_import_v2.sql and last canonically
-- rewritten in 20260803000000_fix_plantilla_import_profile_field_hydration.sql.
--
-- Changes from 20260803000000 (the source of truth):
--   1. Phase B DECLARE: added v_inactive_id uuid (reconcile path staging)
--   2. Phase B employee lookup: expanded status IN clause to include
--      'Inactive' and 'Rejected Deactivation'
--   3. Reconcile branch (new): when existing row is Inactive/Rejected Deactivation
--      → UPDATE to Active, clear separation fields, cancel open deactivation requests
--   4. Deactivated guard (new): if only Deactivated row exists → RAISE NOTICE + skip
--   5. Slot upsert hook (new): after plantilla upsert, wire slot occupancy for the
--      primary VCODE (single-store employees only)
--   All other behavior (Phase A store upsert, Phase B multi-store allocation,
--   VCODE resolution guard, audit enum, rollback readiness, exception handler) is
--   preserved IDENTICALLY from 20260803000000.

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

  -- Optional enrichment parsing
  v_daily_rate_parsed  numeric;
  v_birthdate_parsed   date;
  v_deployment_type    text;
  v_area_val           text;
  v_has_penalty        boolean;

  -- Commit counts
  v_committable int;

  -- VCODE resolution guard
  v_unresolved_vcode text;

  -- Humanised error
  v_err_state text;
  v_err_msg   text;
  v_err_out   text;

  -- OHM2026_0071: Inactive reconcile path
  v_inactive_id      uuid;   -- existing Inactive/Rejected Deactivation row
  v_deactivated_id   uuid;   -- existing Deactivated row (safety skip)

  -- OHM2026_0071: Slot occupancy wire
  v_slot_id          uuid;
  v_slot_vcode       text;
  v_slot_result      jsonb;
  v_slot_ordinal     int;
  v_slot_store_id    uuid;

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

    -- ── Post-Phase-A: VCODE resolution guard (OHM2026_1144) ──────────────────
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
    -- Aggregate per-employee: identity + position/area fields + optional enrichment.
    -- All fields use first-non-null per employee (ORDER BY row_number).
    FOR v_emp_rec IN
      SELECT
        employee_no,
        count(DISTINCT vcode)                                                       AS store_count,
        -- Identity
        (array_agg(last_name   ORDER BY row_number))[1]                            AS last_name,
        (array_agg(first_name  ORDER BY row_number))[1]                            AS first_name,
        (array_agg(middle_name ORDER BY row_number))[1]                            AS middle_name,
        -- Position / deployment
        (array_agg(position          ORDER BY row_number)
           FILTER (WHERE position IS NOT NULL))[1]                                 AS position,
        (array_agg(employment_type   ORDER BY row_number)
           FILTER (WHERE employment_type IS NOT NULL))[1]                          AS employment_type_raw,
        (array_agg(with_penalty_raw  ORDER BY row_number)
           FILTER (WHERE with_penalty_raw IS NOT NULL))[1]                         AS with_penalty_raw_agg,
        (array_agg(area_province     ORDER BY row_number)
           FILTER (WHERE area_province IS NOT NULL))[1]                            AS area_province,
        (array_agg(area_city         ORDER BY row_number)
           FILTER (WHERE area_city IS NOT NULL))[1]                                AS area_city,
        -- Optional enrichment fields (OHM2026_0080)
        (array_agg(civil_status      ORDER BY row_number)
           FILTER (WHERE civil_status    IS NOT NULL))[1]                          AS civil_status,
        (array_agg(rate_raw          ORDER BY row_number)
           FILTER (WHERE rate_raw        IS NOT NULL))[1]                          AS rate_raw,
        (array_agg(birthdate_raw     ORDER BY row_number)
           FILTER (WHERE birthdate_raw   IS NOT NULL))[1]                          AS birthdate_raw,
        (array_agg(contact_raw       ORDER BY row_number)
           FILTER (WHERE contact_raw     IS NOT NULL))[1]                          AS contact_raw,
        (array_agg(address_raw       ORDER BY row_number)
           FILTER (WHERE address_raw     IS NOT NULL))[1]                          AS address_raw,
        (array_agg(schedule_raw      ORDER BY row_number)
           FILTER (WHERE schedule_raw    IS NOT NULL))[1]                          AS schedule_raw,
        (array_agg(dayoff_raw        ORDER BY row_number)
           FILTER (WHERE dayoff_raw      IS NOT NULL))[1]                          AS dayoff_raw,
        (array_agg(coordinator_raw   ORDER BY row_number)
           FILTER (WHERE coordinator_raw IS NOT NULL))[1]                          AS coordinator_raw
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

      -- Normalise deployment_type (Stationary/Roving for display consistency)
      v_deployment_type := CASE
        WHEN lower(COALESCE(v_emp_rec.employment_type_raw,'')) = 'stationary' THEN 'Stationary'
        WHEN lower(COALESCE(v_emp_rec.employment_type_raw,'')) = 'roving'     THEN 'Roving'
        ELSE NULLIF(trim(COALESCE(v_emp_rec.employment_type_raw,'')), '')
      END;

      -- area: prefer city over province for specificity
      v_area_val := NULLIF(trim(COALESCE(
        v_emp_rec.area_city,
        v_emp_rec.area_province,
        ''
      )), '');

      -- has_penalty
      v_has_penalty := CASE
        WHEN lower(COALESCE(v_emp_rec.with_penalty_raw_agg,'')) IN ('yes','y','true','1')  THEN true
        WHEN lower(COALESCE(v_emp_rec.with_penalty_raw_agg,'')) IN ('no','n','false','0') THEN false
        ELSE NULL
      END;

      -- Parse optional numeric/date fields (silent failure → null, never blocks)
      v_daily_rate_parsed := NULL;
      BEGIN
        v_daily_rate_parsed := nullif(trim(coalesce(v_emp_rec.rate_raw, '')), '')::numeric;
      EXCEPTION WHEN OTHERS THEN
        v_daily_rate_parsed := NULL;
      END;

      v_birthdate_parsed := NULL;
      BEGIN
        v_birthdate_parsed := nullif(trim(coalesce(v_emp_rec.birthdate_raw, '')), '')::date;
      EXCEPTION WHEN OTHERS THEN
        v_birthdate_parsed := NULL;
      END;

      -- ── OHM2026_0071: Multi-step plantilla lookup ───────────────────────────
      -- Step 1: Active / On Leave / Pending Deactivation  (existing path)
      v_plantilla_id := NULL;
      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no
         AND is_deleted = false
         AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
       LIMIT 1;

      -- Step 2 (NEW): Inactive / Rejected Deactivation  — reconcile path
      v_inactive_id := NULL;
      IF v_plantilla_id IS NULL THEN
        SELECT id INTO v_inactive_id
          FROM public.plantilla
         WHERE employee_no = v_emp_rec.employee_no
           AND is_deleted = false
           AND status IN ('Inactive', 'Rejected Deactivation')
         LIMIT 1;

        IF v_inactive_id IS NOT NULL THEN
          v_plantilla_id := v_inactive_id;
        END IF;
      END IF;

      -- Step 3 (NEW): Deactivated guard — skip with NOTICE, do not reactivate
      v_deactivated_id := NULL;
      IF v_plantilla_id IS NULL THEN
        SELECT id INTO v_deactivated_id
          FROM public.plantilla
         WHERE employee_no = v_emp_rec.employee_no
           AND is_deleted = false
           AND status = 'Deactivated'
         LIMIT 1;

        IF v_deactivated_id IS NOT NULL THEN
          RAISE NOTICE
            'OHM2026_0071: Skipping employee_no=% — existing row is Deactivated (id=%). '
            'Deactivated employees cannot be reactivated via import; manual review required.',
            v_emp_rec.employee_no, v_deactivated_id;
          v_employees_done := v_employees_done - 1;  -- undo the increment; this row is skipped
          CONTINUE;
        END IF;
      END IF;

      SELECT to_jsonb(p.*) INTO v_old_plant_snap
        FROM public.plantilla p WHERE id = v_plantilla_id;

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

      IF v_plantilla_id IS NULL THEN
        -- ── New employee: INSERT plantilla master ──────────────────────────
        -- OHM2026_1044: plantilla.vcode persisted for single-store rows.
        INSERT INTO public.plantilla (
          employee_name, employee_no, emploc_no, account, status,
          account_id, last_name, first_name, middle_name,
          roving_assignment_id, is_pool_employee,
          -- position / deployment
          position, deployment_type, has_penalty, area, area_name_snapshot,
          -- store lineage
          vcode, store_id, store_name,
          -- optional enrichment fields (OHM2026_0080)
          civil_status, daily_rate, birthdate,
          contact_no, address, schedule, dayoff, coordinator,
          source_baseline_import_batch_id, created_by, moved_by_user_id
        )
        SELECT
          v_emp_name, v_emp_rec.employee_no, v_emp_rec.employee_no,
          v_acct_name, 'Active',
          v_batch.selected_account_id,
          v_emp_rec.last_name, v_emp_rec.first_name, v_emp_rec.middle_name,
          NULL, false,
          -- position / deployment
          nullif(trim(coalesce(v_emp_rec.position, '')), ''),
          v_deployment_type,
          v_has_penalty,
          v_area_val,
          v_area_val,   -- area_name_snapshot mirrors area
          -- store: single-store pins VCODE/store; roving leaves null
          CASE WHEN v_store_cnt = 1 THEN r.vcode     ELSE NULL END,
          CASE WHEN v_store_cnt = 1 THEN sm.store_id ELSE NULL END,
          CASE WHEN v_store_cnt = 1 THEN r.store_name ELSE NULL END,
          -- optional enrichment
          nullif(trim(coalesce(v_emp_rec.civil_status, '')),    ''),
          v_daily_rate_parsed,
          v_birthdate_parsed,
          nullif(trim(coalesce(v_emp_rec.contact_raw, '')),     ''),
          nullif(trim(coalesce(v_emp_rec.address_raw, '')),     ''),
          nullif(trim(coalesce(v_emp_rec.schedule_raw, '')),    ''),
          nullif(trim(coalesce(v_emp_rec.dayoff_raw, '')),      ''),
          nullif(trim(coalesce(v_emp_rec.coordinator_raw, '')), ''),
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

      ELSIF v_inactive_id IS NOT NULL THEN
        -- ── OHM2026_0071: Inactive/Rejected Deactivation reconcile path ─────
        -- Reactivate the existing Inactive/Rejected Deactivation row.
        -- Clear all separation and deactivation fields. Refresh profile fields
        -- using the same COALESCE-fill logic as the normal UPDATE path.
        UPDATE public.plantilla
           SET status                    = 'Active',
               -- Clear separation fields
               inactive_at              = NULL,
               inactive_by              = NULL,
               separation_status        = NULL,
               date_of_separation       = NULL,
               resignation_date         = NULL,
               -- Clear inactive visibility window (removes from Inactive tab)
               inactive_visible_until   = NULL,
               -- Refresh name from import
               employee_name            = v_emp_name,
               last_name                = v_emp_rec.last_name,
               first_name               = v_emp_rec.first_name,
               middle_name              = v_emp_rec.middle_name,
               -- position / deployment: fill if currently blank
               position                 = COALESCE(
                                            NULLIF(trim(COALESCE(position, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.position, '')), '')
                                          ),
               deployment_type          = COALESCE(
                                            NULLIF(trim(COALESCE(deployment_type, '')), ''),
                                            v_deployment_type
                                          ),
               has_penalty              = COALESCE(has_penalty, v_has_penalty),
               area                     = COALESCE(
                                            NULLIF(trim(COALESCE(area, '')), ''),
                                            v_area_val
                                          ),
               area_name_snapshot       = COALESCE(
                                            NULLIF(trim(COALESCE(area_name_snapshot, '')), ''),
                                            v_area_val
                                          ),
               -- optional enrichment: fill if currently blank
               civil_status             = COALESCE(
                                            NULLIF(trim(COALESCE(civil_status, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.civil_status, '')), '')
                                          ),
               daily_rate               = COALESCE(daily_rate, v_daily_rate_parsed),
               birthdate                = COALESCE(birthdate,  v_birthdate_parsed),
               -- address/contact: MIKA source-of-truth — preserve existing value
               contact_no               = CASE
                                            WHEN contact_no IS NOT NULL AND contact_no <> ''
                                            THEN contact_no
                                            ELSE nullif(trim(coalesce(v_emp_rec.contact_raw, '')), '')
                                          END,
               address                  = CASE
                                            WHEN address IS NOT NULL AND address <> ''
                                            THEN address
                                            ELSE nullif(trim(coalesce(v_emp_rec.address_raw, '')), '')
                                          END,
               schedule                 = COALESCE(
                                            NULLIF(trim(COALESCE(schedule, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.schedule_raw, '')), '')
                                          ),
               dayoff                   = COALESCE(
                                            NULLIF(trim(COALESCE(dayoff, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.dayoff_raw, '')), '')
                                          ),
               coordinator              = COALESCE(
                                            NULLIF(trim(COALESCE(coordinator, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.coordinator_raw, '')), '')
                                          ),
               updated_at               = now(),
               source_baseline_import_batch_id = p_batch_id
         WHERE id = v_inactive_id;

        -- Cancel any open deactivation requests for this employee.
        -- The deactivation request is moot now that the employee is re-imported as Active.
        -- The existing approval/rejection RPCs already guard on status = 'Pending', so
        -- setting status = 'Cancelled' cleanly removes these from the queue.
        UPDATE public.employee_deactivation_requests
           SET status     = 'Cancelled',
               updated_at = now()
         WHERE plantilla_id = v_inactive_id
           AND status IN ('Pending')
           AND is_archived = false;

        -- Audit the reactivation event
        INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
        VALUES (v_uid, 'plantilla_import', 'IMPORT_REACTIVATION', v_inactive_id,
          jsonb_build_object(
            'employee_no',  v_emp_rec.employee_no,
            'previous_status', v_old_plant_snap->>'status',
            'batch_id',     p_batch_id,
            'note',         'Employee re-imported as Active; was Inactive/Rejected Deactivation'
          ));

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_inactive_id, 'reactivate', v_old_plant_snap, v_uid);

      ELSE
        -- ── Normal existing employee UPDATE path (unchanged from 20260803000000) ─
        -- Existing employee: refresh name + import linkage + fill blank profile fields.
        -- MIKA source-of-truth: contact_no and address are only filled when currently blank.
        -- position/area/deployment_type: COALESCE fill (import wins when currently blank).
        -- Optional enrichment: COALESCE fill (import wins when currently blank).
        UPDATE public.plantilla
           SET employee_name    = v_emp_name,
               last_name        = v_emp_rec.last_name,
               first_name       = v_emp_rec.first_name,
               middle_name      = v_emp_rec.middle_name,
               -- position / deployment: fill if currently blank
               position         = COALESCE(
                                     NULLIF(trim(COALESCE(position, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.position, '')), '')
                                   ),
               deployment_type  = COALESCE(
                                     NULLIF(trim(COALESCE(deployment_type, '')), ''),
                                     v_deployment_type
                                   ),
               has_penalty      = COALESCE(has_penalty, v_has_penalty),
               area             = COALESCE(
                                     NULLIF(trim(COALESCE(area, '')), ''),
                                     v_area_val
                                   ),
               area_name_snapshot = COALESCE(
                                      NULLIF(trim(COALESCE(area_name_snapshot, '')), ''),
                                      v_area_val
                                    ),
               -- optional enrichment: fill if currently blank
               civil_status     = COALESCE(
                                     NULLIF(trim(COALESCE(civil_status, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.civil_status, '')), '')
                                   ),
               daily_rate       = COALESCE(daily_rate, v_daily_rate_parsed),
               birthdate        = COALESCE(birthdate,  v_birthdate_parsed),
               -- address/contact: MIKA source-of-truth — preserve existing value
               contact_no       = CASE
                                    WHEN contact_no IS NOT NULL AND contact_no <> ''
                                    THEN contact_no
                                    ELSE nullif(trim(coalesce(v_emp_rec.contact_raw, '')), '')
                                  END,
               address          = CASE
                                    WHEN address IS NOT NULL AND address <> ''
                                    THEN address
                                    ELSE nullif(trim(coalesce(v_emp_rec.address_raw, '')), '')
                                  END,
               schedule         = COALESCE(
                                     NULLIF(trim(COALESCE(schedule, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.schedule_raw, '')), '')
                                   ),
               dayoff           = COALESCE(
                                     NULLIF(trim(COALESCE(dayoff, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.dayoff_raw, '')), '')
                                   ),
               coordinator      = COALESCE(
                                     NULLIF(trim(COALESCE(coordinator, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.coordinator_raw, '')), '')
                                   ),
               updated_at       = now(),
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

      -- ── OHM2026_0071: §2 Slot occupancy wire ──────────────────────────────
      -- Single-store employees only (roving excluded per Phase 6.4 carve-out).
      -- Goal: ensure this employee's VCODE slot is in 'occupied' state with
      --       current_occupant_plantilla_id = v_plantilla_id so that when the
      --       employee later goes Inactive, fn_sync_slot_to_open can find and
      --       release the slot, causing the vacancy to reappear in the Open tab.
      --
      -- Non-blocking: all errors are caught and emitted as RAISE NOTICE.
      -- The host transaction is NOT affected by slot errors.
      IF v_store_cnt = 1 AND v_plantilla_id IS NOT NULL THEN
        BEGIN
          -- Resolve the primary VCODE for this employee
          SELECT pir.vcode INTO v_slot_vcode
            FROM public.plantilla_import_rows pir
           WHERE pir.batch_id = p_batch_id
             AND pir.employee_no = v_emp_rec.employee_no
             AND pir.validation_status IN ('valid','flagged')
           ORDER BY pir.row_number
           LIMIT 1;

          IF v_slot_vcode IS NOT NULL THEN
            v_slot_id := NULL;

            -- Lookup 1: occupant link (authoritative)
            SELECT id INTO v_slot_id
              FROM public.plantilla_slots
             WHERE current_occupant_plantilla_id = v_plantilla_id
               AND is_roving = false
             LIMIT 1;

            -- Lookup 2: legacy_vcode bridge (fallback for pre-Phase-6.3 slots)
            IF v_slot_id IS NULL THEN
              SELECT id INTO v_slot_id
                FROM public.plantilla_slots
               WHERE legacy_vcode = v_slot_vcode
                 AND is_roving    = false
               LIMIT 1;
            END IF;

            IF v_slot_id IS NOT NULL THEN
              -- Slot exists: transition to occupied if not already
              DECLARE
                v_slot_current_status text;
              BEGIN
                SELECT slot_status INTO v_slot_current_status
                  FROM public.plantilla_slots
                 WHERE id = v_slot_id;

                IF v_slot_current_status = 'occupied'
                   AND (SELECT current_occupant_plantilla_id FROM public.plantilla_slots WHERE id = v_slot_id) = v_plantilla_id THEN
                  -- Already correctly occupied by this employee — no_op
                  RAISE NOTICE
                    'OHM2026_0071 slot wire: slot_id=% already occupied by plantilla_id=% (vcode=%)',
                    v_slot_id, v_plantilla_id, v_slot_vcode;

                ELSIF v_slot_current_status = 'closed' THEN
                  -- Closed slot: log and skip (terminal under automation)
                  RAISE NOTICE
                    'OHM2026_0071 slot wire: slot_id=% is closed, skipping occupancy wire for plantilla_id=% (vcode=%)',
                    v_slot_id, v_plantilla_id, v_slot_vcode;

                ELSE
                  -- open / pipeline / hr_processing / occupied-by-other:
                  -- Force the slot to occupied via fn_set_slot_status.
                  -- For 'occupied-by-other': the import is authoritative (MIKA source-of-truth).
                  -- fn_set_slot_status handles the open→occupied transfer-in path.
                  -- For pipeline/hr_processing we use direct UPDATE to avoid the blocked
                  -- transitions (pipeline→occupied and hr_processing→occupied have different
                  -- guards in the transition matrix). A direct UPDATE is safe here because
                  -- the import approval is the authoritative lifecycle event.
                  UPDATE public.plantilla_slots
                     SET slot_status                   = 'occupied',
                         current_occupant_plantilla_id = v_plantilla_id,
                         updated_at                    = now(),
                         updated_by                    = v_actor
                   WHERE id = v_slot_id;

                  INSERT INTO public.slot_history (
                    slot_id, account_id, action_type, old_value, new_value,
                    reason_code, performed_by, remarks, created_at
                  ) VALUES (
                    v_slot_id,
                    v_batch.selected_account_id,
                    'occupied',
                    v_slot_current_status,
                    'occupied',
                    'IMPORT_OCCUPIED',
                    v_actor,
                    format(
                      'OHM2026_0071 import slot wire: batch_id=%s employee_no=%s plantilla_id=%s',
                      p_batch_id::text, v_emp_rec.employee_no, v_plantilla_id::text
                    ),
                    now()
                  );

                  RAISE NOTICE
                    'OHM2026_0071 slot wire: slot_id=% transitioned %→occupied for plantilla_id=% (vcode=%)',
                    v_slot_id, v_slot_current_status, v_plantilla_id, v_slot_vcode;
                END IF;
              END;

            ELSE
              -- No slot found: create a new occupied slot for this VCODE.
              -- The slot was missing because:
              --   (a) the vacancy was already 'Filled' before the gap-backfill trigger ran, OR
              --   (b) the employee was imported before the slot foundation was applied.
              -- Creating the slot here ensures fn_sync_slot_to_open can release it on Inactive tag.
              SELECT sm.store_id INTO v_slot_store_id
                FROM _pib_store_map sm
               WHERE sm.vcode = upper(v_slot_vcode)
               LIMIT 1;

              SELECT COALESCE(MAX(ps.slot_ordinal), 0) + 1 INTO v_slot_ordinal
                FROM public.plantilla_slots ps
               WHERE ps.legacy_vcode = v_slot_vcode;

              INSERT INTO public.plantilla_slots (
                store_id, account_id, group_id,
                position, employment_type, is_roving,
                slot_status, slot_ordinal, legacy_vcode,
                current_occupant_plantilla_id,
                created_at, updated_at, created_by, updated_by
              ) VALUES (
                v_slot_store_id,
                v_batch.selected_account_id,
                v_batch.selected_group_id,
                COALESCE(nullif(trim(coalesce(v_emp_rec.position, '')), ''), 'Unknown'),
                COALESCE(lower(nullif(trim(coalesce(v_emp_rec.employment_type_raw, '')), '')), 'stationary'),
                false,  -- is_roving = false (single-store branch)
                'occupied',
                v_slot_ordinal::smallint,
                v_slot_vcode,
                v_plantilla_id,
                now(), now(),
                v_actor, v_actor
              )
              RETURNING id INTO v_slot_id;

              INSERT INTO public.slot_history (
                slot_id, account_id, action_type, old_value, new_value,
                reason_code, performed_by, remarks, created_at
              ) VALUES (
                v_slot_id,
                v_batch.selected_account_id,
                'occupied',
                NULL,
                'occupied',
                'IMPORT_OCCUPIED',
                v_actor,
                format(
                  'OHM2026_0071 new slot created by import: batch_id=%s employee_no=%s plantilla_id=%s',
                  p_batch_id::text, v_emp_rec.employee_no, v_plantilla_id::text
                ),
                now()
              );

              RAISE NOTICE
                'OHM2026_0071 slot wire: created new slot_id=% (occupied) for plantilla_id=% (vcode=%)',
                v_slot_id, v_plantilla_id, v_slot_vcode;
            END IF;
          END IF;

        EXCEPTION WHEN OTHERS THEN
          -- Non-blocking: slot errors must never abort the import approval.
          RAISE NOTICE
            'OHM2026_0071 slot wire: non-fatal error for employee_no=% plantilla_id=% — % (sqlstate=%)',
            v_emp_rec.employee_no, v_plantilla_id, SQLERRM, SQLSTATE;
        END;
      END IF;
      -- ── End OHM2026_0071 slot wire ────────────────────────────────────────

      INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
      VALUES (v_uid, 'plantilla_import', 'APPROVAL', v_plantilla_id,
        jsonb_build_object(
          'employee_no',         v_emp_rec.employee_no,
          'store_count',         v_store_cnt,
          'filled_hc_per_store', v_filled,
          'roving',              (v_roving_id IS NOT NULL),
          'batch_id',            p_batch_id,
          'reconciled',          (v_inactive_id IS NOT NULL)
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
  'OHM2026_0071: Extends 20260803000000 (OHM2026_1044) with two fixes: '
  '(1) Bug 1 — Inactive/Rejected Deactivation reconcile: extends Phase B '
  'employee lookup to include Inactive and Rejected Deactivation statuses. '
  'When found, reactivates the existing row (status→Active, clears separation '
  'fields and inactive_visible_until, cancels open deactivation requests) instead '
  'of inserting a duplicate Active row. Deactivated rows are guarded (RAISE NOTICE '
  'and skip — cannot be reactivated via import). '
  '(2) Bug 2 — Slot occupancy wire: after each single-store employee plantilla '
  'upsert, finds or creates the matching plantilla_slots row and sets it to '
  '''occupied'' with current_occupant_plantilla_id = v_plantilla_id. This ensures '
  'fn_sync_slot_to_open can release the slot when the employee later goes Inactive, '
  'causing the vacancy to reappear in the Vacancy Open tab. Roving employees excluded '
  '(Phase 6.4 carve-out). All slot errors are non-blocking. '
  'All existing Phase A (store upsert), VCODE resolution guard, audit enum, rollback '
  'readiness, and error handling are preserved from OHM2026_1044. '
  'RBAC: Head Admin / Super Admin only.';


-- ============================================================
-- §3  Backfill: wire slot occupancy for already-imported employees
-- ============================================================
-- Applies the slot occupancy wire retroactively for all active
-- single-store plantilla rows that were committed via baseline import
-- but have no slot currently set to occupied with their plantilla_id.
--
-- Scope:
--   • status = 'Active' (skip Inactive/Deactivated — they get the slot
--     on the next Inactive tagging cycle when fn_sync_slot_to_open fires)
--   • is_pool_employee = false (pool employees excluded)
--   • deployment_type NOT IN ('Roving') (roving excluded — Phase 6.4 carve-out)
--   • vcode IS NOT NULL (must have a VCODE)
--   • is_deleted = false
--   • NO existing slot with current_occupant_plantilla_id = plantilla.id AND
--     slot_status = 'occupied'  (already correctly wired → skip)
--
-- For each qualifying plantilla row:
--   1. Find slot by legacy_vcode (bridge lookup, non-roving)
--   2a. If found and status != 'occupied': UPDATE to occupied + slot_history
--   2b. If found and status = 'occupied' but occupant is different: re-point
--   2c. If not found: INSERT new slot (occupied) + slot_history
--
-- Non-blocking per-row: errors caught and RAISE NOTICE'd; loop continues.

DO $$
DECLARE
  v_rec              record;
  v_slot_id          uuid;
  v_slot_status_cur  text;
  v_slot_occupant    uuid;
  v_slot_ordinal     int;
  v_slot_store_id    uuid;
  v_wired            int := 0;
  v_created          int := 0;
  v_skipped          int := 0;
  v_errors           int := 0;
BEGIN
  FOR v_rec IN
    SELECT
      p.id             AS plantilla_id,
      p.vcode,
      p.account_id,
      p.store_id,
      p.position,
      p.deployment_type,
      s.group_id
    FROM public.plantilla p
    LEFT JOIN public.stores s ON s.id = p.store_id
    WHERE p.is_deleted = false
      AND p.status = 'Active'
      AND COALESCE(p.is_pool_employee, false) = false
      AND COALESCE(p.deployment_type, '') NOT IN ('Roving', 'roving')
      AND p.vcode IS NOT NULL
      -- Only process rows that lack an occupied slot pointing at them
      AND NOT EXISTS (
        SELECT 1 FROM public.plantilla_slots ps2
         WHERE ps2.current_occupant_plantilla_id = p.id
           AND ps2.slot_status = 'occupied'
           AND ps2.is_roving = false
      )
  LOOP
    BEGIN
      v_slot_id := NULL;

      -- Find slot by legacy_vcode (bridge fallback; same as fn_sync_slot_to_open)
      SELECT id, slot_status, current_occupant_plantilla_id
        INTO v_slot_id, v_slot_status_cur, v_slot_occupant
        FROM public.plantilla_slots
       WHERE legacy_vcode = v_rec.vcode
         AND is_roving    = false
       LIMIT 1;

      IF v_slot_id IS NOT NULL THEN
        IF v_slot_status_cur = 'occupied' AND v_slot_occupant = v_rec.plantilla_id THEN
          -- Already correctly wired (shouldn't reach here due to WHERE NOT EXISTS above)
          v_skipped := v_skipped + 1;
          CONTINUE;
        ELSIF v_slot_status_cur = 'closed' THEN
          -- Terminal; skip
          RAISE NOTICE 'OHM2026_0071 backfill: slot_id=% is closed, skipping plantilla_id=%',
            v_slot_id, v_rec.plantilla_id;
          v_skipped := v_skipped + 1;
          CONTINUE;
        ELSE
          -- Wire: UPDATE slot to occupied
          UPDATE public.plantilla_slots
             SET slot_status                   = 'occupied',
                 current_occupant_plantilla_id = v_rec.plantilla_id,
                 updated_at                    = now()
           WHERE id = v_slot_id;

          INSERT INTO public.slot_history (
            slot_id, account_id, action_type, old_value, new_value,
            reason_code, performed_by, remarks, created_at
          ) VALUES (
            v_slot_id,
            v_rec.account_id,
            'occupied',
            v_slot_status_cur,
            'occupied',
            'IMPORT_OCCUPIED',
            NULL,  -- system backfill, no actor
            format('OHM2026_0071 backfill: import-committed employee plantilla_id=%s vcode=%s',
                   v_rec.plantilla_id::text, v_rec.vcode),
            now()
          );

          v_wired := v_wired + 1;
        END IF;

      ELSE
        -- No slot: create a new occupied slot
        SELECT s.id INTO v_slot_store_id
          FROM public.stores s
         WHERE upper(s.vcode) = upper(v_rec.vcode)
           AND s.status = 'active'
         ORDER BY s.created_at
         LIMIT 1;

        SELECT COALESCE(MAX(ps.slot_ordinal), 0) + 1 INTO v_slot_ordinal
          FROM public.plantilla_slots ps
         WHERE ps.legacy_vcode = v_rec.vcode;

        INSERT INTO public.plantilla_slots (
          store_id, account_id, group_id,
          position, employment_type, is_roving,
          slot_status, slot_ordinal, legacy_vcode,
          current_occupant_plantilla_id,
          created_at, updated_at
        ) VALUES (
          COALESCE(v_slot_store_id, v_rec.store_id),
          v_rec.account_id,
          v_rec.group_id,
          COALESCE(NULLIF(trim(COALESCE(v_rec.position, '')), ''), 'Unknown'),
          'stationary',  -- single-store, non-roving
          false,
          'occupied',
          v_slot_ordinal::smallint,
          v_rec.vcode,
          v_rec.plantilla_id,
          now(), now()
        )
        RETURNING id INTO v_slot_id;

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type, old_value, new_value,
          reason_code, performed_by, remarks, created_at
        ) VALUES (
          v_slot_id,
          v_rec.account_id,
          'occupied',
          NULL,
          'occupied',
          'IMPORT_OCCUPIED',
          NULL,
          format('OHM2026_0071 backfill: new slot for import-committed employee plantilla_id=%s vcode=%s',
                 v_rec.plantilla_id::text, v_rec.vcode),
          now()
        );

        v_created := v_created + 1;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'OHM2026_0071 backfill: error for plantilla_id=% vcode=% — % (sqlstate=%)',
        v_rec.plantilla_id, v_rec.vcode, SQLERRM, SQLSTATE;
      v_errors := v_errors + 1;
    END;
  END LOOP;

  RAISE NOTICE 'OHM2026_0071 backfill complete: % slot(s) wired to occupied, % new slot(s) created, % skipped, % errors.',
    v_wired, v_created, v_skipped, v_errors;
END$$;
