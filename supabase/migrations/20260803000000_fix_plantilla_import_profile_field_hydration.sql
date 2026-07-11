-- ============================================================
-- OHM2026_1044 — Fix Plantilla Import Profile Field Hydration
-- Migration: 20260731000000_fix_plantilla_import_profile_field_hydration.sql
-- Depends on: 20260730000008_fix_plantilla_import_audit_action_refix.sql
-- ============================================================
-- Root Cause
--   approve_plantilla_import_batch (OHM2026_1145, 20260730000008) lost two
--   accumulated layers of Phase B logic via CREATE OR REPLACE overrides:
--
--   1. Position / deployment_type / area / has_penalty hydration
--      (added by OHM2026_0062 / 20260625000000_hydrate_plantilla_from_baseline_import.sql)
--
--   2. Optional enrichment field commit:
--      civil_status, daily_rate, birthdate, contact_no, address,
--      schedule, dayoff, coordinator
--      (added by OHM2026_0080 / 20260706000000_patch_import_optional_employee_fields.sql)
--
--   Result: every approved import created a plantilla row containing only
--   identity (name/account/emploc_no) — all profile fields displayed as "-"
--   in the employee profile tab.
--
-- Fix
--   Single canonical CREATE OR REPLACE that merges all three bodies:
--     • 20260730000008 — VCODE resolution guard, audit-enum fix, vcode
--       persisted for single-store rows, humanised VCODE_ALREADY_OCCUPIED error
--     • 20260625000000 — position, deployment_type, area, area_name_snapshot,
--       has_penalty written to plantilla on INSERT and COALESCE-filled on UPDATE
--     • 20260706000000 — optional enrichment fields written on INSERT and
--       COALESCE-filled on UPDATE (address/contact follow MIKA source-of-truth)
--
-- Field mapping (plantilla_import_rows → plantilla)
--   position            → plantilla.position        (text)
--   employment_type     → plantilla.deployment_type (normalised: Stationary/Roving)
--   COALESCE(area_city, area_province)
--                       → plantilla.area            (text)
--   area_city           → plantilla.area_name_snapshot (text)
--   with_penalty_raw    → plantilla.has_penalty     (boolean)
--   civil_status        → plantilla.civil_status    (text)
--   rate_raw            → plantilla.daily_rate      (numeric, silent-fail on parse)
--   birthdate_raw       → plantilla.birthdate       (date,    silent-fail on parse)
--   contact_raw         → plantilla.contact_no      (text, MIKA source-of-truth)
--   address_raw         → plantilla.address         (text, MIKA source-of-truth)
--   schedule_raw        → plantilla.schedule        (text)
--   dayoff_raw          → plantilla.dayoff          (text)
--   coordinator_raw     → plantilla.coordinator     (text)
--
-- Replay safety
--   CREATE OR REPLACE — idempotent on re-apply.
--   No DDL changes to tables, indexes, or constraints.
--
-- Validation checklist (run after applying)
--   V1  Import and approve a row with Position=Merchandiser,
--       Employment Type=stationary, Area Province=Pampanga, Area City=Angeles
--       → SELECT position, deployment_type, area FROM plantilla
--           WHERE source_baseline_import_batch_id = '<batch_id>';
--         Expected: Merchandiser | Stationary | Angeles
--
--   V2  Import and approve a row with CIVIL_STATUS=SINGLE, DATE_OF_BIRTH=1990-05-15,
--       CONTACT_NO=09171234567, ADDRESS=123 Sample St
--       → SELECT civil_status, birthdate, contact_no, address FROM plantilla
--           WHERE source_baseline_import_batch_id = '<batch_id>';
--         Expected: SINGLE | 1990-05-15 | 09171234567 | 123 Sample St
--
--   V3  Flutter profile tab for imported employee shows all listed fields
--       (not "-") for Position, Employment Type, Area, Civil Status,
--       Birthdate, Age, Contact, Address.
--
--   V4  Audit enum: approve batch → audit_logs.action = 'APPROVAL' (not 'COMMIT').
--
--   V5  VCODE resolution guard still active:
--       Force a Phase A gap → exception message contains STORE_RESOLUTION_FAILED.
--
--   V6  Existing employee: MIKA contact/address preserved if non-blank;
--       position/area refreshed with COALESCE (import wins when currently blank).
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

      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no
         AND is_deleted = false
         AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
       LIMIT 1;

      SELECT to_jsonb(p.*) INTO v_old_plant_snap
        FROM public.plantilla p WHERE id = v_plantilla_id;

      IF v_plantilla_id IS NULL THEN
        -- New employee: insert plantilla master with all profile fields.
        -- OHM2026_1144: plantilla.vcode persisted for single-store rows.
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

      ELSE
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
  'OHM2026_1044: Canonical merge of all approve_plantilla_import_batch layers. '
  'Restores position/deployment_type/area/has_penalty hydration (lost from OHM2026_0062) '
  'and optional enrichment field commit: civil_status, daily_rate, birthdate, contact_no, '
  'address, schedule, dayoff, coordinator (lost from OHM2026_0080). '
  'Preserves OHM2026_1144/1145: VCODE resolution guard, vcode persisted for single-store '
  'rows, humanised VCODE_ALREADY_OCCUPIED error, audit enum APPROVAL. '
  'MIKA source-of-truth: contact_no/address preserved if non-blank on existing employees. '
  'All other fields: COALESCE-fill (import value wins when currently blank). '
  'RBAC: Head Admin / Super Admin only.';
