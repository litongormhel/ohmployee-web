-- ==============================================================================
-- Migration: 20262606000054_fix_plantilla_import_vacancies_and_flagged_guard.sql
-- Description:
--   1. Add error_message column to public.plantilla_import_batches (for clean
--      error inspection alongside commit_error_detail).
--   2. Enforce Pre-commit Guard in approve_plantilla_import_batch to block batches
--      with unresolved flagged rows before transaction commit begins.
--   3. Fix Phase B1 Vacancies shadow insert to supply required not-null columns:
--      account and position, with comprehensive ON CONFLICT DO UPDATE sync.
--   4. Standardize exception handler to translate SQLSTATE constraint violations
--      into human-readable descriptions and record into both commit_error_detail
--      and error_message.
-- ==============================================================================

-- 1. Schema alignment: ensure error_message column exists on batches table
ALTER TABLE public.plantilla_import_batches
  ADD COLUMN IF NOT EXISTS error_message text;

COMMENT ON COLUMN public.plantilla_import_batches.error_message IS
  'Human-readable explanation of commit or processing failure, synchronized with commit_error_detail.';

-- 2. Update approve_plantilla_import_batch RPC
CREATE OR REPLACE FUNCTION public.approve_plantilla_import_batch(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid        uuid := auth.uid();
  v_actor      uuid := public.get_current_profile_id();
  v_user_name  text;
  v_batch      public.plantilla_import_batches%ROWTYPE;
  v_acct_name  text;

  -- Phase A locals
  v_srow               record;
  v_existing_store_id  uuid;
  v_new_store_id       uuid;
  v_old_store_snap     jsonb;
  v_pen_bool           boolean;
  v_stores_done        int := 0;

  -- Phase B locals
  v_vrow           record;
  v_emp_rec        record;
  v_store_rec      record;
  v_plantilla_id   uuid;
  v_store_cnt      int;
  v_filled         numeric(8,4);
  v_emp_name       text;
  v_old_plant_snap jsonb;
  v_employees_done int := 0;
  v_alloc_done     int := 0;
  v_vacant_slots   int := 0;

  -- Slot claiming
  v_target_slot_id uuid;
  v_next_ordinal   int;

  -- Commit counts & pre-commit guards
  v_flagged_cnt int := 0;
  v_committable int := 0;
  v_approved_timestamp timestamptz;

  -- Error handling
  v_err_state text;
  v_err_msg   text;
  v_err_out   text;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)', v_batch.status USING ERRCODE = '22023';
  END IF;

  SELECT full_name INTO v_user_name FROM public.users_profile WHERE id = v_actor;
  SELECT account_name INTO v_acct_name FROM public.accounts WHERE id = v_batch.selected_account_id;

  -- Pre-commit guard 1: Block approval if there are unresolved flagged rows
  SELECT count(*) INTO v_flagged_cnt
    FROM public.plantilla_import_rows
   WHERE batch_id = p_batch_id
     AND validation_status = 'flagged';

  IF v_flagged_cnt > 0 THEN
    RAISE EXCEPTION 'Cannot approve batch: % flagged rows must be resolved or dismissed first', v_flagged_cnt USING ERRCODE = '22023';
  END IF;

  -- Pre-commit guard 2: Committable includes valid rows with vcode (employee_no may be null for vacant slots)
  SELECT count(*) INTO v_committable
    FROM public.plantilla_import_rows
   WHERE batch_id = p_batch_id
     AND validation_status = 'valid'
     AND vcode IS NOT NULL;

  IF v_committable = 0 THEN
    RAISE EXCEPTION 'COMMIT_EMPTY: no committable rows in batch' USING ERRCODE = '22023';
  END IF;

  BEGIN
    -- Phase A: Store upsert for all committable rows
    FOR v_srow IN
      SELECT DISTINCT ON (vcode)
             vcode, store_name, mother_account, area_province, area_city,
             employment_type, with_penalty_raw, schedule_days, schedule_time,
             row_number, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status = 'valid'
         AND vcode IS NOT NULL
       ORDER BY vcode, row_number
    LOOP
      v_pen_bool := (lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('yes','y','true','1'));

      SELECT to_jsonb(s.*) INTO v_old_store_snap
        FROM public.stores s
       WHERE upper(s.vcode) = upper(v_srow.vcode) AND s.status = 'active'
       ORDER BY s.created_at LIMIT 1;

      IF v_old_store_snap IS NULL THEN
        INSERT INTO public.stores (
          vcode, store_name, mother_account, area_province, area_city,
          employment_type, with_penalty, schedule_days, schedule_time,
          group_id, account_id, status,
          created_by, updated_by, approved_by, approved_at, source_import_id
        ) VALUES (
          v_srow.vcode, v_srow.store_name, v_srow.mother_account, v_srow.area_province, v_srow.area_city,
          COALESCE(v_srow.employment_type, 'stationary'), v_pen_bool, v_srow.schedule_days, v_srow.schedule_time,
          v_batch.selected_group_id, v_batch.selected_account_id, 'active',
          v_uid, v_uid, v_uid, now(), p_batch_id
        ) RETURNING id INTO v_new_store_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_new_store_id, 'insert', NULL, v_uid);
      ELSE
        v_existing_store_id := (v_old_store_snap->>'id')::uuid;

        UPDATE public.stores
           SET store_name      = v_srow.store_name,
               mother_account  = COALESCE(v_srow.mother_account, mother_account),
               area_province   = v_srow.area_province,
               area_city       = v_srow.area_city,
               employment_type = COALESCE(v_srow.employment_type, employment_type),
               with_penalty    = COALESCE(v_pen_bool, with_penalty),
               schedule_days   = COALESCE(v_srow.schedule_days, schedule_days),
               schedule_time   = COALESCE(v_srow.schedule_time, schedule_time),
               updated_by      = v_uid,
               approved_by     = v_uid,
               approved_at     = now(),
               source_import_id = p_batch_id
         WHERE id = v_existing_store_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_existing_store_id, 'update', v_old_store_snap, v_uid);
      END IF;

      v_stores_done := v_stores_done + 1;
    END LOOP;

    -- Phase B1: Vacant Store Slot Creation (rows where employee_no IS NULL)
    FOR v_vrow IN
      SELECT DISTINCT ON (vcode)
             vcode, store_name, position, area_province, area_city, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status = 'valid'
         AND employee_no IS NULL
         AND vcode IS NOT NULL
       ORDER BY vcode, row_number
    LOOP
      SELECT id INTO v_new_store_id FROM public.stores WHERE upper(vcode) = upper(v_vrow.vcode) AND status = 'active' LIMIT 1;

      -- Check if open slot already exists
      IF NOT EXISTS (
        SELECT 1 FROM public.plantilla_slots
         WHERE legacy_vcode = v_vrow.vcode AND slot_status = 'open'
      ) THEN
        INSERT INTO public.plantilla_slots (
          store_id, account_id, group_id,
          position, employment_type, is_roving,
          slot_status, slot_ordinal, legacy_vcode,
          current_occupant_plantilla_id,
          created_at, updated_at, created_by, updated_by
        ) VALUES (
          v_new_store_id, v_batch.selected_account_id, v_batch.selected_group_id,
          COALESCE(v_vrow.position, 'Merchandiser'), 'stationary', false,
          'open', 1, v_vrow.vcode, NULL,
          now(), now(), v_actor, v_actor
        ) RETURNING id INTO v_target_slot_id;

        -- Sync vacancies record for shadow view (with non-null account and position)
        INSERT INTO public.vacancies (
          vcode, account, position, store_name, area_city, province, area_name,
          required_headcount, status, store_id, account_id, group_id,
          created_at, updated_at, created_by
        ) VALUES (
          v_vrow.vcode,
          COALESCE(v_acct_name, 'Unknown Account'),
          COALESCE(v_vrow.position, 'Merchandiser'),
          v_vrow.store_name,
          v_vrow.area_city,
          v_vrow.area_province,
          v_vrow.area_province || ' - ' || v_vrow.area_city,
          1, 'Open', v_new_store_id, v_batch.selected_account_id, v_batch.selected_group_id,
          now(), now(), v_actor
        ) ON CONFLICT (vcode) DO UPDATE
        SET status = 'Open',
            account = EXCLUDED.account,
            position = EXCLUDED.position,
            store_name = EXCLUDED.store_name,
            area_city = EXCLUDED.area_city,
            province = EXCLUDED.province,
            area_name = EXCLUDED.area_name,
            store_id = EXCLUDED.store_id,
            account_id = EXCLUDED.account_id,
            group_id = EXCLUDED.group_id,
            deleted_at = NULL,
            is_archived = false,
            updated_at = now();

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type, old_value, new_value,
          reason_code, performed_by, remarks, created_at
        ) VALUES (
          v_target_slot_id, v_batch.selected_account_id, 'created',
          NULL, 'open', 'IMPORT_VACANT_SLOT', v_actor,
          format('Vacant slot created by baseline import batch %s', p_batch_id), now()
        );

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_vrow.row_id, 'slot', v_target_slot_id, 'insert', NULL, v_uid);

        v_vacant_slots := v_vacant_slots + 1;
      END IF;
    END LOOP;

    -- Phase B2: Assigned Employee Upsert & Slot Claiming
    FOR v_emp_rec IN
      SELECT
        employee_no,
        count(DISTINCT vcode)                                                       AS store_count,
        (array_agg(last_name   ORDER BY row_number))[1]                            AS last_name,
        (array_agg(first_name  ORDER BY row_number))[1]                            AS first_name,
        (array_agg(middle_name ORDER BY row_number))[1]                            AS middle_name,
        (array_agg(position    ORDER BY row_number) FILTER (WHERE position IS NOT NULL))[1] AS position,
        (array_agg(mother_account ORDER BY row_number) FILTER (WHERE mother_account IS NOT NULL))[1] AS mother_account,
        (array_agg(area_province ORDER BY row_number) FILTER (WHERE area_province IS NOT NULL))[1] AS area_province,
        (array_agg(area_city ORDER BY row_number) FILTER (WHERE area_city IS NOT NULL))[1] AS area_city,
        (array_agg(civil_status ORDER BY row_number) FILTER (WHERE civil_status IS NOT NULL))[1] AS civil_status,
        (array_agg(rate_raw ORDER BY row_number) FILTER (WHERE rate_raw IS NOT NULL))[1] AS rate_raw,
        (array_agg(birthdate_raw ORDER BY row_number) FILTER (WHERE birthdate_raw IS NOT NULL))[1] AS birthdate_raw,
        (array_agg(contact_raw ORDER BY row_number) FILTER (WHERE contact_raw IS NOT NULL))[1] AS contact_raw,
        (array_agg(address_raw ORDER BY row_number) FILTER (WHERE address_raw IS NOT NULL))[1] AS address_raw,
        (array_agg(schedule_days ORDER BY row_number) FILTER (WHERE schedule_days IS NOT NULL))[1] AS schedule_days,
        (array_agg(schedule_time ORDER BY row_number) FILTER (WHERE schedule_time IS NOT NULL))[1] AS schedule_time,
        (array_agg(dayoff_raw ORDER BY row_number) FILTER (WHERE dayoff_raw IS NOT NULL))[1] AS dayoff_raw,
        (array_agg(coordinator_raw ORDER BY row_number) FILTER (WHERE coordinator_raw IS NOT NULL))[1] AS coordinator_raw,
        bool_or(needs_hrco) AS needs_hrco_agg,
        (array_agg(resolved_hrco_user_id ORDER BY row_number) FILTER (WHERE resolved_hrco_user_id IS NOT NULL))[1] AS hrco_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status = 'valid'
         AND employee_no IS NOT NULL
       GROUP BY employee_no
    LOOP
      v_employees_done := v_employees_done + 1;
      v_store_cnt := v_emp_rec.store_count;
      v_filled    := round(1.0 / GREATEST(v_store_cnt, 1), 4);
      v_emp_name  := v_emp_rec.last_name || ', ' || v_emp_rec.first_name
                     || COALESCE(' ' || v_emp_rec.middle_name, '');

      -- Plantilla lookup
      v_plantilla_id := NULL;
      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no AND is_deleted = false
       LIMIT 1;

      SELECT to_jsonb(p.*) INTO v_old_plant_snap
        FROM public.plantilla p WHERE id = v_plantilla_id;

      IF v_plantilla_id IS NULL THEN
        -- Insert new plantilla record
        INSERT INTO public.plantilla (
          employee_name, employee_no, emploc_no, account, status,
          account_id, last_name, first_name, middle_name,
          mother_account, position, deployment_type,
          area, area_name_snapshot,
          civil_status, daily_rate, birthdate,
          contact_no, address,
          schedule, schedule_days, schedule_time, dayoff, coordinator,
          hrco_user_id_snapshot, needs_hrco,
          source_baseline_import_batch_id, created_by, moved_by_user_id
        ) VALUES (
          v_emp_name, v_emp_rec.employee_no, v_emp_rec.employee_no, v_acct_name, 'Active',
          v_batch.selected_account_id, v_emp_rec.last_name, v_emp_rec.first_name, v_emp_rec.middle_name,
          v_emp_rec.mother_account, v_emp_rec.position,
          CASE WHEN v_store_cnt > 1 THEN 'Roving' ELSE 'Stationary' END,
          COALESCE(v_emp_rec.area_city, v_emp_rec.area_province),
          COALESCE(v_emp_rec.area_city, v_emp_rec.area_province),
          v_emp_rec.civil_status,
          NULLIF(trim(COALESCE(v_emp_rec.rate_raw,'')), '')::numeric,
          NULLIF(trim(COALESCE(v_emp_rec.birthdate_raw,'')), '')::date,
          v_emp_rec.contact_raw, v_emp_rec.address_raw,
          v_emp_rec.schedule_days, v_emp_rec.schedule_days, v_emp_rec.schedule_time,
          v_emp_rec.dayoff_raw, v_emp_rec.coordinator_raw,
          v_emp_rec.hrco_id, COALESCE(v_emp_rec.needs_hrco_agg, false),
          p_batch_id, v_actor, v_actor
        ) RETURNING id INTO v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'insert', NULL, v_uid);
      ELSE
        -- Update existing plantilla record
        UPDATE public.plantilla
           SET employee_name      = v_emp_name,
               last_name          = v_emp_rec.last_name,
               first_name         = v_emp_rec.first_name,
               middle_name        = v_emp_rec.middle_name,
               mother_account     = COALESCE(v_emp_rec.mother_account, mother_account),
               position           = COALESCE(v_emp_rec.position, position),
               deployment_type    = CASE WHEN v_store_cnt > 1 THEN 'Roving' ELSE 'Stationary' END,
               schedule_days      = COALESCE(v_emp_rec.schedule_days, schedule_days),
               schedule_time      = COALESCE(v_emp_rec.schedule_time, schedule_time),
               dayoff             = COALESCE(v_emp_rec.dayoff_raw, dayoff),
               updated_at         = now(),
               source_baseline_import_batch_id = p_batch_id
         WHERE id = v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'update', v_old_plant_snap, v_uid);
      END IF;

      -- Deactivate old allocations
      UPDATE public.employee_store_allocations
         SET is_active = false, effective_end = CURRENT_DATE
       WHERE employee_no = v_emp_rec.employee_no
         AND is_active
         AND account_id = v_batch.selected_account_id;

      -- Store allocations loop
      FOR v_store_rec IN
        SELECT DISTINCT ON (pir.vcode)
               pir.vcode, pir.store_name, pir.schedule_days, pir.schedule_time
          FROM public.plantilla_import_rows pir
         WHERE pir.batch_id = p_batch_id
           AND pir.employee_no = v_emp_rec.employee_no
           AND pir.validation_status = 'valid'
         ORDER BY pir.vcode, pir.row_number
      LOOP
        SELECT id INTO v_new_store_id FROM public.stores WHERE upper(vcode) = upper(v_store_rec.vcode) AND status = 'active' LIMIT 1;

        INSERT INTO public.employee_store_allocations (
          plantilla_id, employee_no,
          store_id, vcode, store_name,
          account_id, group_id,
          filled_hc, active_store_count,
          schedule_days, schedule_time,
          effective_start, is_active,
          source_import_batch_id, created_by
        ) VALUES (
          v_plantilla_id, v_emp_rec.employee_no,
          v_new_store_id, v_store_rec.vcode, v_store_rec.store_name,
          v_batch.selected_account_id, v_batch.selected_group_id,
          v_filled, v_store_cnt,
          v_store_rec.schedule_days, v_store_rec.schedule_time,
          CURRENT_DATE, true,
          p_batch_id, v_actor
        );
        v_alloc_done := v_alloc_done + 1;

        -- Safeguard 3: Vacant-to-Occupied Slot Claiming
        v_target_slot_id := NULL;
        SELECT id INTO v_target_slot_id
          FROM public.plantilla_slots
         WHERE legacy_vcode = v_store_rec.vcode
           AND slot_status = 'open'
         ORDER BY slot_ordinal ASC
         LIMIT 1;

        IF v_target_slot_id IS NOT NULL THEN
          -- Claim and transition open vacant slot to occupied
          UPDATE public.plantilla_slots
             SET slot_status = 'occupied',
                 current_occupant_plantilla_id = v_plantilla_id,
                 updated_at = now(),
                 updated_by = v_actor
           WHERE id = v_target_slot_id;

          -- Close / mark linked vacancies as Filled
          UPDATE public.vacancies
             SET status = 'Filled',
                 updated_at = now()
           WHERE vcode = v_store_rec.vcode
             AND status = 'Open';

          INSERT INTO public.slot_history (
            slot_id, account_id, action_type, old_value, new_value,
            reason_code, performed_by, remarks, created_at
          ) VALUES (
            v_target_slot_id, v_batch.selected_account_id, 'occupied',
            'open', 'occupied', 'IMPORT_CLAIM_VACANT', v_actor,
            format('Claimed vacant slot for employee %s via batch %s', v_emp_rec.employee_no, p_batch_id),
            now()
          );
        ELSE
          -- Create additional slot with incremented ordinal if needed
          IF NOT EXISTS (
            SELECT 1 FROM public.plantilla_slots
             WHERE legacy_vcode = v_store_rec.vcode
               AND current_occupant_plantilla_id = v_plantilla_id
          ) THEN
            SELECT COALESCE(MAX(slot_ordinal), 0) + 1 INTO v_next_ordinal
              FROM public.plantilla_slots
             WHERE legacy_vcode = v_store_rec.vcode;

            INSERT INTO public.plantilla_slots (
              store_id, account_id, group_id,
              position, employment_type, is_roving,
              slot_status, slot_ordinal, legacy_vcode,
              current_occupant_plantilla_id,
              created_at, updated_at, created_by, updated_by
            ) VALUES (
              v_new_store_id, v_batch.selected_account_id, v_batch.selected_group_id,
              COALESCE(v_emp_rec.position, 'Unknown'),
              CASE WHEN v_store_cnt > 1 THEN 'roving' ELSE 'stationary' END,
              (v_store_cnt > 1),
              'occupied', v_next_ordinal::smallint, v_store_rec.vcode,
              v_plantilla_id,
              now(), now(), v_actor, v_actor
            ) RETURNING id INTO v_target_slot_id;

            INSERT INTO public.slot_history (
              slot_id, account_id, action_type, old_value, new_value,
              reason_code, performed_by, remarks, created_at
            ) VALUES (
              v_target_slot_id, v_batch.selected_account_id, 'occupied',
              NULL, 'occupied', 'IMPORT_OCCUPIED', v_actor,
              format('New occupied slot ordinal %s for employee %s', v_next_ordinal, v_emp_rec.employee_no),
              now()
            );
          END IF;
        END IF;

      END LOOP;

    END LOOP;

    -- Safeguard 2: Zero-Edit Lock False-Positive Guard
    -- Ensure approved_at is recorded AFTER all entity changes finish.
    v_approved_timestamp := clock_timestamp();

    UPDATE public.plantilla_import_batches
       SET status              = 'approved',
           approved_by         = v_uid,
           approved_at         = v_approved_timestamp,
           approved_by_name    = v_user_name,
           committed_stores    = v_stores_done,
           committed_employees = v_employees_done,
           rollback_ready      = true,
           updated_at          = v_approved_timestamp
     WHERE id = p_batch_id;

    RETURN jsonb_build_object(
      'batch_id',            p_batch_id,
      'status',              'approved',
      'stores_committed',    v_stores_done,
      'employees_committed', v_employees_done,
      'vacant_slots_created', v_vacant_slots,
      'allocations_created', v_alloc_done
    );

  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_err_state = RETURNED_SQLSTATE,
      v_err_msg   = MESSAGE_TEXT;

    IF v_err_state = '23502' THEN
      v_err_out := format('Commit failed due to missing required field: %s (SQLSTATE %s)', v_err_msg, v_err_state);
    ELSIF v_err_state = '23505' THEN
      v_err_out := format('Commit failed due to unique constraint conflict: %s (SQLSTATE %s)', v_err_msg, v_err_state);
    ELSIF v_err_state = '23503' THEN
      v_err_out := format('Commit failed due to foreign key reference conflict: %s (SQLSTATE %s)', v_err_msg, v_err_state);
    ELSE
      v_err_out := format('[%s] %s', v_err_state, v_err_msg);
    END IF;

    UPDATE public.plantilla_import_batches
       SET status              = 'commit_failed',
           commit_error_detail = v_err_out,
           error_message       = v_err_out,
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
