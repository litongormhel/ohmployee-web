-- Migration: 20262606000059_fix_plantilla_field_inheritance_and_mapping.sql
-- Purpose:
--   1. Create deterministic parsing helper functions safe_parse_numeric and safe_parse_date.
--   2. Update approve_plantilla_import_batch RPC (Phase B2) to inherit and populate:
--      - Store / Primary Store (store_name, vcode, store_id)
--      - Date Hired / Deployed (date_hired from date_hired_raw)
--      - Base Rate (rate and daily_rate from rate_raw)
--      - Residential Address (address from address_raw)
--      - Contact number, birthdate, and date_of_birth
--      - Active plantilla_store_links sync for roving covered stores
--      - ADR-002 Invariant 9 strict compliance for needs_hrco
--   3. Update get_web_plantilla_detail RPC to project:
--      - primary_store_name, date_deployed, base_rate_masked, residential_address,
--        contact_number, and covered_stores fallback to employee_store_allocations
--   4. Idempotently backfill existing imported records in public.plantilla with missing
--      store_name, vcode, rate, date_hired, or address from plantilla_import_rows.

-- 1. Deterministic Helper Functions
CREATE OR REPLACE FUNCTION public.safe_parse_numeric(p_str text)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_str IS NULL OR trim(p_str) = '' THEN
    RETURN NULL;
  END IF;
  RETURN regexp_replace(p_str, '[^0-9.]', '', 'g')::numeric;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.safe_parse_date(p_str text)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_str IS NULL OR trim(p_str) = '' THEN
    RETURN NULL;
  END IF;
  BEGIN
    RETURN p_str::date;
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      RETURN to_date(p_str, 'MM/DD/YYYY');
    EXCEPTION WHEN OTHERS THEN
      BEGIN
        RETURN to_date(p_str, 'MM/DD/YY');
      EXCEPTION WHEN OTHERS THEN
        RETURN NULL;
      END;
    END;
  END;
END;
$$;

-- 2. Update approve_plantilla_import_batch RPC
CREATE OR REPLACE FUNCTION public.approve_plantilla_import_batch(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid            uuid := auth.uid();
  v_actor          uuid := public.get_current_profile_id();
  v_user_name      text;
  v_batch          public.plantilla_import_batches%ROWTYPE;
  v_acct_name      text;
  v_acct_hrco_id   uuid;
  v_acct_hrco_name text;

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
  v_primary_store_id uuid;
  v_parsed_rate    numeric;
  v_parsed_date_hired date;
  v_parsed_birthdate  date;
  v_store_cnt      int;
  v_filled         numeric(8,4);
  v_emp_name       text;
  v_old_plant_snap jsonb;
  v_employees_done int := 0;
  v_alloc_done     int := 0;
  v_vacant_slots   int := 0;

  -- HRCO resolution locals
  v_final_hrco_id   uuid;
  v_final_hrco_name text;
  v_needs_hrco      boolean;

  -- Slot claiming & assignment locals
  v_target_slot_id uuid;
  v_next_ordinal   int;
  v_batch_created_slot_ids uuid[] := '{}'::uuid[];

  -- Commit counts & pre-commit guards
  v_blocked_cnt int := 0;
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
  IF v_batch.status NOT IN ('pending_approval', 'commit_failed') THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval or commit_failed can be approved (current=%)', v_batch.status USING ERRCODE = '22023';
  END IF;

  SELECT full_name INTO v_user_name FROM public.users_profile WHERE id = v_actor;
  SELECT account_name, hrco_user_id INTO v_acct_name, v_acct_hrco_id
    FROM public.accounts WHERE id = v_batch.selected_account_id;

  IF v_acct_hrco_id IS NOT NULL THEN
    SELECT full_name INTO v_acct_hrco_name
      FROM public.users_profile
     WHERE id = v_acct_hrco_id;
  END IF;

  -- Pre-commit guard 1: Block approval strictly if there are hard-blocked rows
  SELECT count(*) INTO v_blocked_cnt
    FROM public.plantilla_import_rows
   WHERE batch_id = p_batch_id
     AND validation_status = 'blocked';

  IF v_blocked_cnt > 0 THEN
    RAISE EXCEPTION 'Cannot approve batch: % blocked rows must be resolved or removed first', v_blocked_cnt USING ERRCODE = '22023';
  END IF;

  -- Pre-commit guard 2: Committable includes valid and flagged rows with vcode (employee_no may be null for vacant slots)
  SELECT count(*) INTO v_committable
    FROM public.plantilla_import_rows
   WHERE batch_id = p_batch_id
     AND validation_status IN ('valid', 'flagged')
     AND vcode IS NOT NULL;

  IF v_committable = 0 THEN
    RAISE EXCEPTION 'COMMIT_EMPTY: no committable rows in batch' USING ERRCODE = '22023';
  END IF;

  BEGIN
    -- Phase A: Store upsert for all committable rows (valid + flagged)
    FOR v_srow IN
      SELECT DISTINCT ON (vcode)
             vcode, store_name, mother_account, area_province, area_city,
             employment_type, with_penalty_raw, schedule_days, schedule_time,
             row_number, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid', 'flagged')
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
          group_id, account_id, status, hrco_user_id,
          created_by, updated_by, approved_by, approved_at, source_import_id
        ) VALUES (
          v_srow.vcode, v_srow.store_name, v_srow.mother_account, v_srow.area_province, v_srow.area_city,
          COALESCE(v_srow.employment_type, 'stationary'), v_pen_bool, v_srow.schedule_days, v_srow.schedule_time,
          v_batch.selected_group_id, v_batch.selected_account_id, 'active', v_acct_hrco_id,
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
               hrco_user_id    = COALESCE(v_acct_hrco_id, hrco_user_id),
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

    -- Phase B1: Vacant Store Slot Creation (committable rows where employee_no IS NULL)
    FOR v_vrow IN
      SELECT vcode, store_name, position, area_province, area_city, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid', 'flagged')
         AND employee_no IS NULL
         AND vcode IS NOT NULL
       ORDER BY vcode, row_number
    LOOP
      SELECT id INTO v_new_store_id FROM public.stores WHERE upper(vcode) = upper(v_vrow.vcode) AND status = 'active' LIMIT 1;

      -- Calculate next available ordinal for this store
      SELECT COALESCE(MAX(slot_ordinal), 0) + 1 INTO v_next_ordinal
        FROM public.plantilla_slots
       WHERE store_id = v_new_store_id OR (store_id IS NULL AND upper(legacy_vcode) = upper(v_vrow.vcode));

      INSERT INTO public.plantilla_slots (
        store_id, account_id, group_id,
        position, employment_type, is_roving,
        slot_status, slot_ordinal, legacy_vcode,
        current_occupant_plantilla_id,
        created_at, updated_at, created_by, updated_by
      ) VALUES (
        v_new_store_id, v_batch.selected_account_id, v_batch.selected_group_id,
        COALESCE(v_vrow.position, 'Merchandiser'), 'stationary', false,
        'open', v_next_ordinal::smallint, v_vrow.vcode, NULL,
        now(), now(), v_actor, v_actor
      ) RETURNING id INTO v_target_slot_id;

      v_batch_created_slot_ids := array_append(v_batch_created_slot_ids, v_target_slot_id);

      -- Sync vacancies record for shadow view
      INSERT INTO public.vacancies (
        vcode, account, position, store_name, area_city, province, area_name,
        required_headcount, status, store_id, account_id, group_id,
        hrco_user_id, hrco_name,
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
        v_acct_hrco_id, v_acct_hrco_name,
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
          required_headcount = GREATEST(vacancies.required_headcount, 1),
          hrco_user_id = COALESCE(EXCLUDED.hrco_user_id, vacancies.hrco_user_id),
          hrco_name = COALESCE(EXCLUDED.hrco_name, vacancies.hrco_name),
          deleted_at = NULL,
          is_archived = false,
          updated_at = now();

      INSERT INTO public.slot_history (
        slot_id, account_id, action_type, old_value, new_value,
        reason_code, performed_by, remarks, created_at
      ) VALUES (
        v_target_slot_id, v_batch.selected_account_id, 'created',
        NULL, 'open',
        CASE WHEN EXISTS (SELECT 1 FROM public.slot_reason_codes WHERE code = 'IMPORT_VACANT_SLOT') THEN 'IMPORT_VACANT_SLOT' ELSE NULL END,
        v_actor,
        format('Vacant slot created by baseline import batch %s', p_batch_id), now()
      );

      INSERT INTO public.plantilla_import_commit_snapshots
        (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
      VALUES (p_batch_id, v_vrow.row_id, 'slot', v_target_slot_id, 'insert', NULL, v_uid);

      v_vacant_slots := v_vacant_slots + 1;
    END LOOP;

    -- Phase B2: Assigned Employee Upsert & Slot Provisioning (valid + flagged)
    FOR v_emp_rec IN
      SELECT
        employee_no,
        count(DISTINCT vcode)                                                       AS store_count,
        (array_agg(last_name   ORDER BY row_number))[1]                            AS last_name,
        (array_agg(first_name  ORDER BY row_number))[1]                            AS first_name,
        (array_agg(middle_name ORDER BY row_number))[1]                            AS middle_name,
        (array_agg(position    ORDER BY row_number) FILTER (WHERE position IS NOT NULL))[1] AS position,
        (array_agg(vcode       ORDER BY row_number) FILTER (WHERE vcode IS NOT NULL))[1] AS primary_vcode,
        (array_agg(store_name  ORDER BY row_number) FILTER (WHERE store_name IS NOT NULL))[1] AS primary_store_name,
        (array_agg(mother_account ORDER BY row_number) FILTER (WHERE mother_account IS NOT NULL))[1] AS mother_account,
        (array_agg(area_province ORDER BY row_number) FILTER (WHERE area_province IS NOT NULL))[1] AS area_province,
        (array_agg(area_city ORDER BY row_number) FILTER (WHERE area_city IS NOT NULL))[1] AS area_city,
        (array_agg(civil_status ORDER BY row_number) FILTER (WHERE civil_status IS NOT NULL))[1] AS civil_status,
        (array_agg(rate_raw ORDER BY row_number) FILTER (WHERE rate_raw IS NOT NULL))[1] AS rate_raw,
        (array_agg(birthdate_raw ORDER BY row_number) FILTER (WHERE birthdate_raw IS NOT NULL))[1] AS birthdate_raw,
        (array_agg(date_hired_raw ORDER BY row_number) FILTER (WHERE date_hired_raw IS NOT NULL))[1] AS date_hired_raw,
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
         AND validation_status IN ('valid', 'flagged')
         AND employee_no IS NOT NULL
       GROUP BY employee_no
    LOOP
      v_employees_done := v_employees_done + 1;
      v_store_cnt := v_emp_rec.store_count;
      v_filled    := round(1.0 / GREATEST(v_store_cnt, 1), 4);
      v_emp_name  := v_emp_rec.last_name || ', ' || v_emp_rec.first_name
                     || COALESCE(' ' || v_emp_rec.middle_name, '');

      -- Resolve Primary Store ID
      v_primary_store_id := NULL;
      IF v_emp_rec.primary_vcode IS NOT NULL THEN
        SELECT id INTO v_primary_store_id
          FROM public.stores
         WHERE upper(vcode) = upper(v_emp_rec.primary_vcode) AND status = 'active'
         ORDER BY created_at LIMIT 1;
      END IF;

      -- Parse numeric rate and dates
      v_parsed_rate := public.safe_parse_numeric(v_emp_rec.rate_raw);
      v_parsed_date_hired := public.safe_parse_date(v_emp_rec.date_hired_raw);
      v_parsed_birthdate := public.safe_parse_date(v_emp_rec.birthdate_raw);

      -- HRCO resolution: row-level first, then Account assigned HRCO fallback
      v_final_hrco_id := COALESCE(v_emp_rec.hrco_id, v_acct_hrco_id);
      IF v_final_hrco_id IS NOT NULL THEN
        IF v_final_hrco_id = v_acct_hrco_id AND v_acct_hrco_name IS NOT NULL THEN
          v_final_hrco_name := v_acct_hrco_name;
        ELSE
          SELECT full_name INTO v_final_hrco_name
            FROM public.users_profile
           WHERE id = v_final_hrco_id;
        END IF;
        v_needs_hrco := false;
      ELSE
        v_final_hrco_name := NULL;
        v_needs_hrco := true;
      END IF;

      -- Plantilla lookup
      v_plantilla_id := NULL;
      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no AND is_deleted = false
       LIMIT 1;

      SELECT to_jsonb(p.*) INTO v_old_plant_snap
        FROM public.plantilla p WHERE id = v_plantilla_id;

      IF v_plantilla_id IS NULL THEN
        -- Insert new plantilla record with all inherited fields
        INSERT INTO public.plantilla (
          employee_name, employee_no, emploc_no, account, status,
          account_id, last_name, first_name, middle_name,
          mother_account, position, deployment_type,
          store_id, store_name, vcode,
          area, area_name_snapshot,
          civil_status, rate, daily_rate, birthdate, date_of_birth, date_hired,
          contact_no, address,
          schedule, schedule_days, schedule_time, dayoff, coordinator,
          hrco_user_id_snapshot, hrco_name, needs_hrco,
          source_baseline_import_batch_id, created_by, moved_by_user_id
        ) VALUES (
          v_emp_name, v_emp_rec.employee_no, v_emp_rec.employee_no, v_acct_name, 'Active',
          v_batch.selected_account_id, v_emp_rec.last_name, v_emp_rec.first_name, v_emp_rec.middle_name,
          v_emp_rec.mother_account, v_emp_rec.position,
          CASE WHEN v_store_cnt > 1 THEN 'Roving' ELSE 'Stationary' END,
          v_primary_store_id, v_emp_rec.primary_store_name, v_emp_rec.primary_vcode,
          COALESCE(v_emp_rec.area_city, v_emp_rec.area_province),
          COALESCE(v_emp_rec.area_city, v_emp_rec.area_province),
          v_emp_rec.civil_status,
          v_parsed_rate,
          v_parsed_rate,
          v_parsed_birthdate,
          v_parsed_birthdate,
          v_parsed_date_hired,
          v_emp_rec.contact_raw, v_emp_rec.address_raw,
          v_emp_rec.schedule_days, v_emp_rec.schedule_days, v_emp_rec.schedule_time,
          v_emp_rec.dayoff_raw, v_emp_rec.coordinator_raw,
          v_final_hrco_id, v_final_hrco_name, v_needs_hrco,
          p_batch_id, v_actor, v_actor
        ) RETURNING id INTO v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'insert', NULL, v_uid);
      ELSE
        -- Update existing plantilla record with inherited fields
        UPDATE public.plantilla
           SET employee_name      = v_emp_name,
               last_name          = v_emp_rec.last_name,
               first_name         = v_emp_rec.first_name,
               middle_name        = v_emp_rec.middle_name,
               mother_account     = COALESCE(v_emp_rec.mother_account, mother_account),
               position           = COALESCE(v_emp_rec.position, position),
               deployment_type    = CASE WHEN v_store_cnt > 1 THEN 'Roving' ELSE 'Stationary' END,
               store_id           = COALESCE(v_primary_store_id, store_id),
               store_name         = COALESCE(v_emp_rec.primary_store_name, store_name),
               vcode              = COALESCE(v_emp_rec.primary_vcode, vcode),
               rate               = COALESCE(v_parsed_rate, rate),
               daily_rate         = COALESCE(v_parsed_rate, daily_rate),
               date_hired         = COALESCE(v_parsed_date_hired, date_hired),
               address            = COALESCE(v_emp_rec.address_raw, address),
               contact_no         = COALESCE(v_emp_rec.contact_raw, contact_no),
               birthdate          = COALESCE(v_parsed_birthdate, birthdate),
               date_of_birth      = COALESCE(v_parsed_birthdate, date_of_birth),
               civil_status       = COALESCE(v_emp_rec.civil_status, civil_status),
               schedule_days      = COALESCE(v_emp_rec.schedule_days, schedule_days),
               schedule_time      = COALESCE(v_emp_rec.schedule_time, schedule_time),
               dayoff             = COALESCE(v_emp_rec.dayoff_raw, dayoff),
               hrco_user_id_snapshot = COALESCE(v_final_hrco_id, hrco_user_id_snapshot),
               hrco_name          = COALESCE(v_final_hrco_name, hrco_name),
               needs_hrco         = CASE WHEN v_final_hrco_id IS NOT NULL THEN false ELSE COALESCE(v_emp_rec.needs_hrco_agg, needs_hrco) END,
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

      -- Store allocations loop (committable valid + flagged)
      FOR v_store_rec IN
        SELECT DISTINCT ON (pir.vcode)
               pir.vcode, pir.store_name, pir.schedule_days, pir.schedule_time
          FROM public.plantilla_import_rows pir
         WHERE pir.batch_id = p_batch_id
           AND pir.employee_no = v_emp_rec.employee_no
           AND pir.validation_status IN ('valid', 'flagged')
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

        -- Sync active roving link in plantilla_store_links for safe view consistency
        INSERT INTO public.plantilla_store_links (
          plantilla_id, vcode, store_name, account, status, linked_at
        ) VALUES (
          v_plantilla_id, v_store_rec.vcode, v_store_rec.store_name, v_acct_name, 'Active', now()
        ) ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL)
        DO UPDATE SET
          store_name = EXCLUDED.store_name,
          account = EXCLUDED.account,
          status = 'Active';

        -- Store-level idempotent slot reuse, pre-existing vacant claiming, or slot provisioning
        v_target_slot_id := NULL;

        -- Step 1: Check if employee already occupies an active slot in this store
        SELECT id INTO v_target_slot_id
          FROM public.plantilla_slots
         WHERE (store_id = v_new_store_id OR (store_id IS NULL AND upper(legacy_vcode) = upper(v_store_rec.vcode)))
           AND current_occupant_plantilla_id = v_plantilla_id
           AND slot_status IN ('occupied', 'filled')
         LIMIT 1;

        IF v_target_slot_id IS NOT NULL THEN
          -- Re-import / idempotent update of existing active slot for this employee in this store
          UPDATE public.plantilla_slots
             SET store_id        = COALESCE(store_id, v_new_store_id),
                 position        = COALESCE(v_emp_rec.position, position),
                 is_roving       = (v_store_cnt > 1),
                 employment_type = CASE WHEN v_store_cnt > 1 THEN 'roving' ELSE 'stationary' END,
                 updated_at      = now(),
                 updated_by      = v_actor
           WHERE id = v_target_slot_id;

        ELSE
          -- Step 2: Employee does NOT already have an active slot here.
          -- Can we claim an open vacant slot that existed prior to this import (NOT created in Phase B1 of this batch)?
          SELECT id INTO v_target_slot_id
            FROM public.plantilla_slots
           WHERE (store_id = v_new_store_id OR (store_id IS NULL AND upper(legacy_vcode) = upper(v_store_rec.vcode)))
             AND slot_status = 'open'
             AND (v_batch_created_slot_ids IS NULL OR id <> ALL(v_batch_created_slot_ids))
           ORDER BY slot_ordinal ASC
           LIMIT 1;

          IF v_target_slot_id IS NOT NULL THEN
            -- Claim pre-existing vacant slot
            UPDATE public.plantilla_slots
               SET slot_status = 'occupied',
                   store_id = COALESCE(store_id, v_new_store_id),
                   position = COALESCE(v_emp_rec.position, position),
                   is_roving = (v_store_cnt > 1),
                   employment_type = CASE WHEN v_store_cnt > 1 THEN 'roving' ELSE 'stationary' END,
                   current_occupant_plantilla_id = v_plantilla_id,
                   updated_at = now(),
                   updated_by = v_actor
             WHERE id = v_target_slot_id;

            -- Close / mark linked vacancies as Filled
            UPDATE public.vacancies
               SET status = 'Filled',
                   updated_at = now()
             WHERE upper(vcode) = upper(v_store_rec.vcode)
               AND status = 'Open';

            INSERT INTO public.slot_history (
              slot_id, account_id, action_type, old_value, new_value,
              reason_code, performed_by, remarks, created_at
            ) VALUES (
              v_target_slot_id, v_batch.selected_account_id, 'occupied',
              'open', 'occupied',
              CASE WHEN EXISTS (SELECT 1 FROM public.slot_reason_codes WHERE code = 'IMPORT_CLAIM_VACANT') THEN 'IMPORT_CLAIM_VACANT' ELSE NULL END,
              v_actor,
              format('Claimed vacant slot for employee %s via batch %s', v_emp_rec.employee_no, p_batch_id),
              now()
            );

          ELSE
            -- Step 3: No pre-existing open slot exists. Create a new occupied slot with incremented ordinal
            SELECT COALESCE(MAX(slot_ordinal), 0) + 1 INTO v_next_ordinal
              FROM public.plantilla_slots
             WHERE store_id = v_new_store_id OR (store_id IS NULL AND upper(legacy_vcode) = upper(v_store_rec.vcode));

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
              NULL, 'occupied',
              CASE WHEN EXISTS (SELECT 1 FROM public.slot_reason_codes WHERE code = 'IMPORT_OCCUPIED') THEN 'IMPORT_OCCUPIED' ELSE NULL END,
              v_actor,
              format('New occupied slot ordinal %s for employee %s', v_next_ordinal, v_emp_rec.employee_no),
              now()
            );
          END IF;
        END IF;

      END LOOP;

    END LOOP;

    -- Update batch status
    v_approved_timestamp := clock_timestamp();
    UPDATE public.plantilla_import_batches
       SET status             = 'approved',
           approved_by        = v_uid,
           approved_at        = v_approved_timestamp,
           rejection_reason   = NULL,
           commit_error       = NULL,
           stores_created     = v_stores_done,
           employees_created  = v_employees_done,
           allocations_created= v_alloc_done
     WHERE id = p_batch_id;

    RETURN jsonb_build_object(
      'success', true,
      'batch_id', p_batch_id,
      'status', 'approved',
      'stores_processed', v_stores_done,
      'employees_processed', v_employees_done,
      'allocations_created', v_alloc_done,
      'vacant_slots_created', v_vacant_slots,
      'approved_at', v_approved_timestamp
    );

  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_err_state = RETURNED_SQLSTATE,
      v_err_msg   = MESSAGE_TEXT;
    v_err_out := format('[%s] %s', v_err_state, v_err_msg);

    UPDATE public.plantilla_import_batches
       SET status       = 'commit_failed',
           commit_error = v_err_out
     WHERE id = p_batch_id;

    RAISE EXCEPTION 'COMMIT_FAILED: %', v_err_out USING ERRCODE = v_err_state;
  END;
END;
$func$;

REVOKE ALL ON FUNCTION public.approve_plantilla_import_batch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_batch(uuid) TO authenticated;

-- 3. Drop and Recreate get_web_plantilla_detail RPC
DROP FUNCTION IF EXISTS public.get_web_plantilla_detail(uuid);

CREATE OR REPLACE FUNCTION public.get_web_plantilla_detail(p_employee_id uuid)
RETURNS TABLE (
  plantilla_id                uuid,
  employee_name               text,
  employee_no                 text,
  last_name                   text,
  first_name                  text,
  middle_name                 text,
  emploc_no                   text,
  account_id                  uuid,
  account_name                text,
  group_id                    uuid,
  group_name                  text,
  store_id                    uuid,
  store_name                  text,
  primary_store_name          text,
  area                        text,
  province_id                 uuid,
  chain_id                    uuid,
  position_title              text,
  position_id                 uuid,
  deployment_type             text,
  is_roving                   boolean,
  roving_assignment_id        uuid,
  roving_store_count          integer,
  roving_stores               jsonb,
  covered_stores              jsonb,
  schedule                    text,
  rest_day                    text,
  status                      text,
  is_active                   boolean,
  is_inactive                 boolean,
  is_pending_deactivation     boolean,
  is_deactivated              boolean,
  date_hired                  date,
  date_deployed               date,
  tenure_months               integer,
  age                         integer,
  separation_status           text,
  date_of_separation          date,
  over_headcount              boolean,
  hr_emploc_id                uuid,
  onboarding_linked           boolean,
  vcode                       text,
  vacancy_id                  uuid,
  vacancy_code_snapshot       text,
  employee_name_snapshot      text,
  hrco_user_id_snapshot       uuid,
  hrco_name                   text,
  deactivation_overlay        jsonb,
  inactive_at                 timestamp with time zone,
  for_deactivation_at         timestamp with time zone,
  deactivated_at              timestamp with time zone,
  transfer_overlay            jsonb,
  source_headcount_request_id uuid,
  is_hc_placeholder           boolean,
  has_masked_fields           boolean,
  masked_fields               jsonb,
  base_rate_masked            text,
  residential_address         text,
  contact_number              text,
  has_penalty                 boolean,
  row_capabilities            jsonb,
  created_at                  timestamp with time zone,
  updated_at                  timestamp with time zone,
  moved_by_user_id            uuid,
  last_mika_synced_at         timestamp with time zone,
  last_mika_synced_by         uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid   uuid := auth.uid();
  v_profile_id uuid;
  v_role_name  text;
  v_role_level integer;
  v_cov_stores jsonb;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web plantilla detail requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_name, r.role_level
  INTO v_profile_id, v_role_name, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web plantilla detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.v_plantilla_safe p
    WHERE p.id = p_employee_id
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR p.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          WHERE us.user_id = v_profile_id AND us.account_id = p.account_id
        )
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          JOIN public.accounts ac ON ac.id = p.account_id
          WHERE us.user_id = v_profile_id
            AND us.account_id IS NULL
            AND us.group_id = ac.group_id
        )
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb
          JOIN public.accounts ac ON ac.id = p.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (
              SELECT 1 FROM public.user_scopes us_any
              WHERE us_any.user_id = v_profile_id
                AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
            )
            AND (up_fb.account_id = p.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ) THEN
    RAISE EXCEPTION 'forbidden: web plantilla detail record is not found or caller has insufficient access'
      USING ERRCODE = '42501';
  END IF;

  -- Build covered stores jsonb prioritizing active employee_store_allocations
  SELECT COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'stable_key', esa.id,
          'store_name', esa.store_name,
          'vcode', esa.vcode,
          'is_primary', (esa.vcode = pl.vcode OR esa.store_id = pl.store_id),
          'allocation_percent', round(esa.filled_hc * 100)
        ) ORDER BY esa.created_at ASC
      )
      FROM public.employee_store_allocations esa
      WHERE esa.plantilla_id = p_employee_id AND esa.is_active = true
    ),
    p.roving_stores,
    '[]'::jsonb
  ) INTO v_cov_stores
  FROM public.v_plantilla_safe p
  JOIN public.plantilla pl ON pl.id = p.id
  WHERE p.id = p_employee_id;

  RETURN QUERY
  SELECT
    p.id                                                                       AS plantilla_id,
    p.employee_name,
    p.employee_no,
    pl.last_name,
    pl.first_name,
    pl.middle_name,
    pl.emploc_no,
    p.account_id,
    a.account_name,
    a.group_id,
    g.group_name,
    COALESCE(p.store_id, pl.store_id)                                         AS store_id,
    COALESCE(p.store_name, pl.store_name)                                     AS store_name,
    COALESCE(p.store_name, pl.store_name, (SELECT esa.store_name FROM public.employee_store_allocations esa WHERE esa.plantilla_id = p.id AND esa.is_active ORDER BY esa.created_at LIMIT 1)) AS primary_store_name,
    p.area,
    p.province_id,
    p.chain_id,
    p."position"                                                               AS position_title,
    p.position_id,
    p.deployment_type,
    (COALESCE(p.deployment_type, '') = 'Roving' OR p.roving_assignment_id IS NOT NULL OR jsonb_array_length(v_cov_stores) > 1) AS is_roving,
    p.roving_assignment_id,
    GREATEST(COALESCE(p.roving_store_count, 0), jsonb_array_length(v_cov_stores))::integer AS roving_store_count,
    COALESCE(p.roving_stores, '[]'::jsonb)                                     AS roving_stores,
    v_cov_stores                                                               AS covered_stores,
    p.schedule,
    pl.rest_day,
    p.status,
    (p.status = 'Active')                                                      AS is_active,
    (p.status <> 'Active')                                                     AS is_inactive,
    (p.status IN ('Pending Deactivation', 'For Deactivation'))                 AS is_pending_deactivation,
    (p.status = 'Deactivated')                                                 AS is_deactivated,
    COALESCE(p.date_hired, pl.date_hired)                                      AS date_hired,
    COALESCE(p.date_hired, pl.date_hired)                                      AS date_deployed,
    p.tenure_months,
    p.age,
    p.separation_status,
    p.date_of_separation,
    COALESCE(p.over_headcount, FALSE)                                          AS over_headcount,
    p.hr_emploc_id,
    (p.hr_emploc_id IS NOT NULL)                                               AS onboarding_linked,
    COALESCE(p.vcode, pl.vcode)                                                AS vcode,
    pl.vacancy_id,
    pl.vacancy_code_snapshot,
    pl.employee_name_snapshot,
    pl.hrco_user_id_snapshot,
    p.hrco_name,
    jsonb_build_object(
      'is_pending',         (p.status IN ('Pending Deactivation', 'For Deactivation')),
      'is_rejected',        (p.status = 'Rejected Deactivation'),
      'is_deactivated',     (p.status = 'Deactivated'),
      'deactivated_at',     p.deactivated_at,
      'deactivation_reason', p.deactivation_reason,
      'display_label', CASE
        WHEN p.status IN ('Pending Deactivation', 'For Deactivation', 'Pending') THEN 'Pending Deactivation'
        WHEN p.status IN ('Rejected Deactivation', 'Rejected') THEN 'Rejected Deactivation'
        WHEN p.status IN ('Deactivated', 'Approved') THEN 'Deactivated'
        ELSE NULL
      END
    )                                                                          AS deactivation_overlay,
    pl.inactive_at,
    pl.for_deactivation_at,
    p.deactivated_at,
    jsonb_build_object(
      'has_transfer_history',      (pl.transferred_from_store_id IS NOT NULL),
      'transferred_from_store_id', pl.transferred_from_store_id,
      'transferred_from_store_name', ts.store_name,
      'last_transfer_at',          pl.last_transfer_at
    )                                                                          AS transfer_overlay,
    p.source_headcount_request_id,
    (p.source_headcount_request_id IS NOT NULL)                                AS is_hc_placeholder,
    (p.sss_no IS NOT NULL OR p.philhealth_no IS NOT NULL OR p.pagibig_no IS NOT NULL OR p.atm_no_masked IS NOT NULL) AS has_masked_fields,
    (
      '[]'::jsonb
      || CASE WHEN p.atm_no_masked   IS NOT NULL THEN '["atm_no"]'::jsonb      ELSE '[]'::jsonb END
      || CASE WHEN p.sss_no          IS NOT NULL THEN '["sss_no"]'::jsonb      ELSE '[]'::jsonb END
      || CASE WHEN p.philhealth_no   IS NOT NULL THEN '["philhealth_no"]'::jsonb ELSE '[]'::jsonb END
      || CASE WHEN p.pagibig_no      IS NOT NULL THEN '["pagibig_no"]'::jsonb   ELSE '[]'::jsonb END
    )                                                                          AS masked_fields,
    CASE
      WHEN pl.rate IS NOT NULL THEN '₱' || to_char(pl.rate, 'FM999,999,990.00')
      WHEN pl.daily_rate IS NOT NULL THEN '₱' || to_char(pl.daily_rate, 'FM999,999,990.00')
      ELSE NULL
    END                                                                        AS base_rate_masked,
    COALESCE(pl.address, p.area)                                               AS residential_address,
    pl.contact_no                                                              AS contact_number,
    COALESCE(p.has_penalty, FALSE)                                             AS has_penalty,
    jsonb_build_object(
      'can_view_detail',              TRUE,
      'can_request_deactivation',     (
        p.status NOT IN ('Pending Deactivation', 'For Deactivation', 'Deactivated')
        AND (public.i_have_full_access() OR public.i_am_ops())
      ),
      'can_resubmit_deactivation',    (
        p.status = 'Rejected Deactivation'
        AND (public.i_have_full_access() OR public.i_am_ops())
      ),
      'can_transfer',                 (
        p.status = 'Active'
        AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
      ),
      'can_request_deletion',         (
        p.status = 'Active'
        AND (public.i_have_full_access() OR public.i_am_ops())
      ),
      'can_update_employment_status', (
        p.status = 'Active'
        AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
      ),
      'can_archive',                  (COALESCE(v_role_level, 0) >= 100)
    )                                                                          AS row_capabilities,
    p.created_at,
    p.updated_at,
    pl.moved_by_user_id,
    p.last_mika_synced_at,
    p.last_mika_synced_by
  FROM public.v_plantilla_safe p
  JOIN public.plantilla pl ON pl.id = p.id
  LEFT JOIN public.accounts a ON a.id = p.account_id
  LEFT JOIN public.groups g ON g.id = a.group_id
  LEFT JOIN public.stores ts ON ts.id = pl.transferred_from_store_id
  WHERE p.id = p_employee_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_web_plantilla_detail(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_web_plantilla_detail(uuid) TO authenticated;

-- 4. Idempotent Data Backfill for Existing Imported Plantilla Records
UPDATE public.plantilla p
   SET vcode = COALESCE(p.vcode, sub.vcode),
       store_name = COALESCE(p.store_name, sub.store_name),
       store_id = COALESCE(p.store_id, sub.store_id, (SELECT s.id FROM public.stores s WHERE upper(s.vcode) = upper(sub.vcode) AND s.status = 'active' LIMIT 1)),
       rate = COALESCE(p.rate, public.safe_parse_numeric(sub.rate_raw), p.daily_rate),
       daily_rate = COALESCE(p.daily_rate, public.safe_parse_numeric(sub.rate_raw), p.rate),
       date_hired = COALESCE(p.date_hired, public.safe_parse_date(sub.date_hired_raw)),
       address = COALESCE(p.address, sub.address_raw),
       contact_no = COALESCE(p.contact_no, sub.contact_raw),
       birthdate = COALESCE(p.birthdate, public.safe_parse_date(sub.birthdate_raw), p.date_of_birth),
       date_of_birth = COALESCE(p.date_of_birth, public.safe_parse_date(sub.birthdate_raw), p.birthdate),
       needs_hrco = CASE WHEN (p.hrco_user_id_snapshot IS NOT NULL OR (p.hrco_name IS NOT NULL AND trim(p.hrco_name) <> '')) THEN false ELSE p.needs_hrco END
  FROM (
    SELECT DISTINCT ON (employee_no)
           employee_no, vcode, store_name, resolved_store_id AS store_id,
           rate_raw, date_hired_raw, address_raw, contact_raw, birthdate_raw
      FROM public.plantilla_import_rows
     WHERE employee_no IS NOT NULL
     ORDER BY employee_no, created_at DESC, row_number ASC
  ) sub
 WHERE p.employee_no = sub.employee_no
   AND (
     p.vcode IS NULL
     OR p.store_name IS NULL
     OR p.rate IS NULL
     OR p.date_hired IS NULL
     OR p.address IS NULL
   );
