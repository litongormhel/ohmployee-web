-- Migration: 20262606000062_fix_vacancy_account_linkage.sql
-- Purpose:
--   1. Harden approve_plantilla_import_batch to strictly inherit and propagate
--      account_id, group_id, and account_name to stores, plantilla_slots, and vacancies.
--   2. Update approve_vacancy_import to look up and populate store_id.
--   3. Update vw_vacancy_detail and get_web_vacancy_detail to dynamically resolve
--      account_name and group_name from foreign key relations rather than falling
--      back to "Unknown Account".
--   4. Idempotently backfill existing stores, plantilla_slots, and vacancies
--      (including CPRVJV13) repairing orphaned account_id, group_id, and account text.

-- ============================================================================
-- Section 1. Update approve_plantilla_import_batch RPC
-- ============================================================================
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

  -- Target linkage locals
  v_store_acct_id     uuid;
  v_store_grp_id      uuid;
  v_target_account_id uuid;
  v_target_group_id   uuid;
  v_target_acct_name  text;

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
               account_id      = COALESCE(stores.account_id, v_batch.selected_account_id),
               group_id        = COALESCE(stores.group_id, v_batch.selected_group_id),
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
      v_new_store_id := NULL;
      v_store_acct_id := NULL;
      v_store_grp_id := NULL;

      SELECT id, account_id, group_id
        INTO v_new_store_id, v_store_acct_id, v_store_grp_id
        FROM public.stores
       WHERE upper(vcode) = upper(v_vrow.vcode) AND status = 'active'
       ORDER BY created_at LIMIT 1;

      v_target_account_id := COALESCE(v_batch.selected_account_id, v_store_acct_id);
      v_target_group_id   := COALESCE(v_batch.selected_group_id, v_store_grp_id);

      IF v_target_account_id IS NOT NULL AND (v_acct_name IS NULL OR v_acct_name = 'Unknown Account') THEN
        SELECT account_name INTO v_target_acct_name FROM public.accounts WHERE id = v_target_account_id;
      ELSE
        v_target_acct_name := v_acct_name;
      END IF;

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
        v_new_store_id, v_target_account_id, v_target_group_id,
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
        COALESCE(v_target_acct_name, v_acct_name, 'Unknown Account'),
        COALESCE(v_vrow.position, 'Merchandiser'),
        v_vrow.store_name,
        v_vrow.area_city,
        v_vrow.area_province,
        v_vrow.area_province || ' - ' || v_vrow.area_city,
        1, 'Open', v_new_store_id, v_target_account_id, v_target_group_id,
        v_acct_hrco_id, v_acct_hrco_name,
        now(), now(), v_actor
      ) ON CONFLICT (vcode) DO UPDATE
      SET status = 'Open',
          account = CASE
            WHEN EXCLUDED.account IS NOT NULL AND EXCLUDED.account <> 'Unknown Account' THEN EXCLUDED.account
            ELSE COALESCE(NULLIF(vacancies.account, 'Unknown Account'), EXCLUDED.account)
          END,
          position = EXCLUDED.position,
          store_name = EXCLUDED.store_name,
          area_city = EXCLUDED.area_city,
          province = EXCLUDED.province,
          area_name = EXCLUDED.area_name,
          store_id = COALESCE(EXCLUDED.store_id, vacancies.store_id),
          account_id = COALESCE(EXCLUDED.account_id, vacancies.account_id),
          group_id = COALESCE(EXCLUDED.group_id, vacancies.group_id),
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
        v_target_slot_id, v_target_account_id, 'created',
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
               coordinator        = COALESCE(v_emp_rec.coordinator_raw, coordinator),
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
        v_new_store_id := NULL;
        v_store_acct_id := NULL;
        v_store_grp_id := NULL;

        SELECT id, account_id, group_id
          INTO v_new_store_id, v_store_acct_id, v_store_grp_id
          FROM public.stores
         WHERE upper(vcode) = upper(v_store_rec.vcode) AND status = 'active'
         ORDER BY created_at LIMIT 1;

        v_target_account_id := COALESCE(v_batch.selected_account_id, v_store_acct_id);
        v_target_group_id   := COALESCE(v_batch.selected_group_id, v_store_grp_id);

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
          v_target_account_id, v_target_group_id,
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
                 account_id      = COALESCE(account_id, v_target_account_id),
                 group_id        = COALESCE(group_id, v_target_group_id),
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
                   account_id = COALESCE(account_id, v_target_account_id),
                   group_id = COALESCE(group_id, v_target_group_id),
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
              v_target_slot_id, v_target_account_id, 'occupied',
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
              v_new_store_id, v_target_account_id, v_target_group_id,
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
              v_target_slot_id, v_target_account_id, 'occupied',
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

-- ============================================================================
-- Section 2. Update approve_vacancy_import RPC (store_id propagation)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.approve_vacancy_import(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid        uuid := auth.uid();
  v_actor      uuid := public.get_current_profile_id();
  v_batch      public.vacancy_import_batches%ROWTYPE;
  v_acct_name  text;
  v_grp_name   text;

  v_r              record;
  v_existing       record;
  v_vac_id         uuid;
  v_store_id       uuid;
  v_vac_done       int := 0;
  v_vac_restored   int := 0;
  v_app_done       int := 0;
  v_app_name       text;
  v_app_contact    text;
BEGIN
  -- Auth
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.vacancy_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  SELECT account_name INTO v_acct_name
    FROM public.accounts WHERE id = v_batch.selected_account_id;
  SELECT group_name INTO v_grp_name
    FROM public.groups WHERE id = v_batch.selected_group_id;

  -- Preflight applicant contact values before any commit DML.
  FOR v_r IN
    SELECT row_number, contact_number
      FROM public.vacancy_import_rows
     WHERE batch_id = p_batch_id
       AND validation_status IN ('valid','flagged')
       AND vcode IS NOT NULL
       AND derived_tab = 'pipeline'
     ORDER BY row_number
  LOOP
    v_app_contact := regexp_replace(btrim(COALESCE(v_r.contact_number, '')), '[^0-9]', '', 'g');

    IF v_app_contact <> ''
       AND NOT (
         v_app_contact ~ '^9[0-9]{9}$'
         OR v_app_contact ~ '^09[0-9]{9}$'
       ) THEN
      RAISE EXCEPTION
        'VACANCY_IMPORT_CONTACT_INVALID: Invalid applicant contact number on row %. Use 10 digits starting with 9 or 11 digits starting with 09.',
        v_r.row_number
        USING ERRCODE = '22023';
    END IF;
  END LOOP;

  -- Commit rows
  FOR v_r IN
    SELECT *
      FROM public.vacancy_import_rows
     WHERE batch_id = p_batch_id
       AND validation_status IN ('valid','flagged')
       AND vcode IS NOT NULL
     ORDER BY row_number
  LOOP
    -- Defence-in-depth: never duplicate an existing ACTIVE official VCODE.
    IF EXISTS (
      SELECT 1 FROM public.vacancies vv
      WHERE upper(vv.vcode) = upper(v_r.vcode)
        AND COALESCE(vv.is_archived, false) = false
        AND vv.deleted_at IS NULL
    ) THEN
      CONTINUE;
    END IF;

    -- Look up store_id if store exists for this vcode
    v_store_id := NULL;
    SELECT s.id INTO v_store_id
      FROM public.stores s
     WHERE upper(s.vcode) = upper(v_r.vcode) AND s.status = 'active'
     ORDER BY s.created_at LIMIT 1;

    -- Restore-or-insert: if a soft-deleted Import-Vacancy row exists for
    -- this VCODE, restore it in place.
    SELECT id
      INTO v_existing
      FROM public.vacancies vv
     WHERE upper(vv.vcode) = upper(v_r.vcode)
       AND vv.deleted_at IS NOT NULL
       AND vv.source_vacancy_import_batch_id IS NOT NULL
     ORDER BY vv.deleted_at DESC NULLS LAST
     LIMIT 1
     FOR UPDATE;

    IF FOUND THEN
      -- Restore + refresh fields from the new import row, and re-point
      -- provenance to the new batch.
      UPDATE public.vacancies
         SET deleted_at                     = NULL,
             is_archived                    = false,
             status                         = 'Open',
             has_pending_closure            = false,
             account                        = COALESCE(v_acct_name, account),
             account_id                     = v_batch.selected_account_id,
             group_id                       = v_batch.selected_group_id,
             store_id                       = COALESCE(v_store_id, vacancies.store_id),
             position                       = v_r.position,
             chain                          = v_r.chain,
             province                       = v_r.province,
             store_name                     = v_r.store_name,
             area_city                      = v_r.city,
             employment_type                = v_r.employment_type,
             request_type                   = v_r.request_type_norm,
             vacancy_type                   = CASE
                                                WHEN v_r.request_type_norm = 'Replacement'
                                                THEN 'Replacement'
                                                ELSE 'New'
                                             END,
             vacant_date                    = v_r.vacant_date_raw::date,
             target_fill_date               = NULLIF(v_r.target_fill_date_raw,'')::date,
             required_headcount             = COALESCE(v_r.hc_raw::int, 1),
             has_penalty                    = COALESCE(v_r.with_penalty_norm, false),
             hrco_name                      = v_r.hrco,
             hrco_mobile                    = v_r.contact_number,
             source                         = 'manual',
             source_vacancy_import_batch_id = p_batch_id,
             updated_by                     = v_actor
       WHERE id = v_existing.id
       RETURNING id INTO v_vac_id;

      v_vac_restored := v_vac_restored + 1;
    ELSE
      -- Fresh insert (no prior import-vacancy soft-deleted row for this VCODE).
      INSERT INTO public.vacancies (
        vcode, account, position, status,
        account_id, group_id, store_id,
        chain, province, store_name, area_city,
        employment_type, request_type, vacancy_type,
        vacant_date, target_fill_date,
        required_headcount, has_penalty,
        hrco_name, hrco_mobile,
        source, source_vacancy_import_batch_id,
        created_by, created_by_user_id, is_archived, has_pending_closure
      ) VALUES (
        v_r.vcode, v_acct_name, v_r.position, 'Open',
        v_batch.selected_account_id, v_batch.selected_group_id, v_store_id,
        v_r.chain, v_r.province, v_r.store_name, v_r.city,
        v_r.employment_type, v_r.request_type_norm,
        CASE WHEN v_r.request_type_norm = 'Replacement' THEN 'Replacement' ELSE 'New' END,
        v_r.vacant_date_raw::date,
        NULLIF(v_r.target_fill_date_raw,'')::date,
        COALESCE(v_r.hc_raw::int, 1), COALESCE(v_r.with_penalty_norm, false),
        v_r.hrco, v_r.contact_number,
        'manual', p_batch_id,
        v_actor, v_actor, false, false
      ) RETURNING id INTO v_vac_id;
    END IF;

    v_vac_done := v_vac_done + 1;

    -- Pipeline rows seed one applicant (presence of applicant => Pipeline tab)
    IF v_r.derived_tab = 'pipeline' THEN
      v_app_name := trim(
        COALESCE(v_r.applicant_last_name,'') ||
        CASE WHEN v_r.applicant_first_name IS NOT NULL
             THEN ', ' || v_r.applicant_first_name ELSE '' END ||
        CASE WHEN v_r.applicant_middle_name IS NOT NULL
             THEN ' ' || v_r.applicant_middle_name ELSE '' END);
      IF v_app_name = '' OR v_app_name = ',' THEN
        v_app_name := COALESCE(v_r.applicant_first_name, v_r.applicant_last_name, 'Applicant');
      END IF;

      v_app_contact := regexp_replace(btrim(COALESCE(v_r.contact_number, '')), '[^0-9]', '', 'g');
      v_app_contact := CASE
                         WHEN v_app_contact = '' THEN NULL
                         WHEN v_app_contact ~ '^9[0-9]{9}$' THEN '0' || v_app_contact
                         ELSE v_app_contact
                       END;

      INSERT INTO public.applicants (
        vacancy_vcode, full_name, full_name_snapshot,
        last_name, first_name, middle_name,
        contact_number, status, created_by, updated_by
      ) VALUES (
        v_r.vcode, v_app_name, v_app_name,
        v_r.applicant_last_name, v_r.applicant_first_name, v_r.applicant_middle_name,
        v_app_contact, COALESCE(v_r.applicant_status, 'New'),
        v_actor, v_actor
      );
      v_app_done := v_app_done + 1;
    END IF;
  END LOOP;

  -- Batch status update
  UPDATE public.vacancy_import_batches
     SET status               = 'approved',
         approved_by          = v_uid,
         approved_at          = now(),
         committed_vacancies  = v_vac_done,
         committed_applicants = v_app_done,
         updated_at           = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'APPROVAL', p_batch_id,
    jsonb_build_object(
      'status', 'approved',
      'committed_vacancies', v_vac_done,
      'restored_vacancies', v_vac_restored,
      'committed_applicants', v_app_done));

  RETURN jsonb_build_object(
    'success', true,
    'batch_id', p_batch_id,
    'committed_vacancies', v_vac_done,
    'restored_vacancies', v_vac_restored,
    'committed_applicants', v_app_done);

EXCEPTION WHEN OTHERS THEN
  UPDATE public.vacancy_import_batches
     SET status              = 'commit_failed',
         commit_error_detail = SQLERRM,
         updated_at          = now()
   WHERE id = p_batch_id;
  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object('event', 'commit_failed', 'error', SQLERRM));
  RAISE EXCEPTION 'COMMIT_FAILED: %', SQLERRM USING ERRCODE = '22000';
END$func$;

REVOKE ALL ON FUNCTION public.approve_vacancy_import(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_vacancy_import(uuid) TO authenticated;

-- ============================================================================
-- Section 3. Update vw_vacancy_detail view
-- ============================================================================
CREATE OR REPLACE VIEW public.vw_vacancy_detail AS
 WITH applicant_stats AS (
          SELECT a_1.vacancy_vcode,
            count(*) FILTER (WHERE COALESCE(a_1.is_archived, false) = false AND (replace(replace(lower(btrim(COALESCE(a_1.status, ''::text))), ' '::text, '_'::text), '-'::text, '_'::text) <> ALL (ARRAY['failed'::text, 'backout'::text, 'rejected'::text, 'did_not_report'::text, 'rejected_by_ops'::text, 'withdrew'::text, 'confirmed_onboard'::text]))) AS active_applicant_count,
            count(*) FILTER (WHERE COALESCE(a_1.is_archived, false) = false AND a_1.status = 'Confirmed Onboard'::text) AS confirmed_onboard_count,
            max(a_1.hired_at) FILTER (WHERE COALESCE(a_1.is_archived, false) = false AND a_1.status = 'Confirmed Onboard'::text) AS latest_hire_at,
            count(*) FILTER (WHERE COALESCE(a_1.is_archived, false) = false AND a_1.status = 'Confirmed Onboard'::text AND COALESCE(a_1.hired_visible_until, a_1.hired_at + '7 days'::interval) > now()) > 0 AS has_recent_hire
           FROM public.applicants a_1
          GROUP BY a_1.vacancy_vcode
        )
 SELECT v.id,
    v.vcode,
    COALESCE(
      NULLIF(a.account_name, ''),
      NULLIF(ast.account_name, ''),
      NULLIF(v.account, 'Unknown Account'),
      v.account
    ) AS account,
    COALESCE(v.account_id, a.id, st.account_id, st_vcode.account_id) AS account_id,
    COALESCE(NULLIF(btrim(v.store_name), ''::text), NULLIF(btrim(v.store_branch), ''::text),
        CASE
            WHEN v.is_pool_vacancy = true OR v.source = 'pool'::text OR v.vcode ~~ '%GHQ%'::text OR lower(btrim(COALESCE(v.account, ''::text))) = 'moses hq'::text OR lower(btrim(COALESCE(a.account_name, ''::text))) = 'moses hq'::text OR lower(btrim(COALESCE(g.group_name, ga.group_name, ''::text))) = 'global hq'::text OR v.home_account_id = '3946ffdd-d826-4fc7-bb9e-356a32dcd152'::uuid THEN 'Moses HQ'::text
            ELSE NULL::text
        END) AS store_name,
    COALESCE(v.store_id, st.id, st_vcode.id) AS store_id,
    v.area_name,
    v.area_city,
    v.province,
    v.store_branch,
    v."position",
    v.position_id,
    v.employment_type,
    v.status,
    CASE
        WHEN v.is_archived = true OR (v.status = ANY (ARRAY['Closed'::text, 'Archived'::text])) THEN 'Archived'::text
        -- Safeguard: Only mark 'Hired' when confirmed onboards actually reach or exceed required headcount
        WHEN COALESCE(s.confirmed_onboard_count, 0::bigint) >= GREATEST(COALESCE(v.required_headcount, 1), 1)
             OR v.status = 'Filled'::text THEN 'Hired'::text
        WHEN COALESCE(v.has_pending_closure, false) = true
             OR LOWER(COALESCE(v.closure_request_status, '')) = 'pending'
             OR LOWER(COALESCE(v.status, '')) IN ('closure', 'for_closure')
             OR EXISTS (
               SELECT 1 FROM public.vacancy_closure_requests vcr
               WHERE vcr.vacancy_vcode = v.vcode AND LOWER(vcr.status) = 'pending'
             ) THEN 'For Closure'::text
        -- Capacity-aware rule: Stays 'Open' as long as occupied slots (confirmed + active pipeline) < hc_total
        WHEN (COALESCE(s.confirmed_onboard_count, 0::bigint) + COALESCE(s.active_applicant_count, 0::bigint)) < GREATEST(COALESCE(v.required_headcount, 1), 1) THEN 'Open'::text
        WHEN COALESCE(s.active_applicant_count, 0::bigint) > 0 THEN 'Pipeline'::text
        ELSE 'Open'::text
    END AS derived_status,
    v.source,
    v.source_vacancy_request_id,
    v.source_plantilla_id,
    v.vacancy_type,
    v.urgency_level,
    v.target_fill_date,
    v.required_headcount AS hc_needed,
    v.triggered_by_user_id,
    v.triggered_by_name,
    v.vacant_date,
    CURRENT_DATE - v.vacant_date AS aging_days,
    v.created_at,
    v.created_by,
    v.updated_at,
    v.is_archived,
    v.archived_at,
    v.closure_request_status,
    v.has_pending_closure,
    COALESCE(s.active_applicant_count, 0::bigint) AS active_applicant_count,
    COALESCE(s.confirmed_onboard_count, 0::bigint) AS confirmed_onboard_count,
    s.latest_hire_at,
    v.assigned_encoder_id,
    v.has_reliever,
    v.reliever_name,
    v.requested_by_user_id,
    v.requested_date,
    COALESCE(v.group_id, a.group_id, st.group_id, st_vcode.group_id, ga.id, gst.id) AS group_id,
    COALESCE(g.group_name, ga.group_name, gst.group_name) AS group_name,
    COALESCE(
      v.hrco_user_id,
      st.hrco_user_id,
      st_vcode.hrco_user_id,
      a.hrco_user_id,
      (
        SELECT us_acc.user_id
        FROM public.user_scopes us_acc
        JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
        JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
        WHERE us_acc.account_id = COALESCE(v.account_id, a.id, st.account_id, st_vcode.account_id)
          AND r_sc.role_name = 'HRCO'::text
          AND up_sc.is_active = true
          AND up_sc.archived_at IS NULL
        ORDER BY us_acc.created_at ASC
        LIMIT 1
      ),
      (
        SELECT us_grp.user_id
        FROM public.user_scopes us_grp
        JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
        JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
        WHERE us_grp.group_id = COALESCE(v.group_id, a.group_id, st.group_id, st_vcode.group_id)
          AND us_grp.account_id IS NULL
          AND r_scg.role_name = 'HRCO'::text
          AND up_scg.is_active = true
          AND up_scg.archived_at IS NULL
        ORDER BY us_grp.created_at ASC
        LIMIT 1
      )
    ) AS hrco_user_id,
    COALESCE(
      CASE WHEN up_hrco.is_active = true AND r_hrco.role_name = 'HRCO'::text THEN up_hrco.full_name ELSE NULL::text END,
      CASE WHEN up_st_hrco.is_active = true AND r_st_hrco.role_name = 'HRCO'::text THEN up_st_hrco.full_name ELSE NULL::text END,
      CASE WHEN up_a_hrco.is_active = true AND r_a_hrco.role_name = 'HRCO'::text THEN up_a_hrco.full_name ELSE NULL::text END,
      (
        SELECT up_sc.full_name
        FROM public.user_scopes us_acc
        JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
        JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
        WHERE us_acc.account_id = COALESCE(v.account_id, a.id, st.account_id, st_vcode.account_id)
          AND r_sc.role_name = 'HRCO'::text
          AND up_sc.is_active = true
          AND up_sc.archived_at IS NULL
        ORDER BY us_acc.created_at ASC
        LIMIT 1
      ),
      (
        SELECT up_scg.full_name
        FROM public.user_scopes us_grp
        JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
        JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
        WHERE us_grp.group_id = COALESCE(v.group_id, a.group_id, st.group_id, st_vcode.group_id)
          AND us_grp.account_id IS NULL
          AND r_scg.role_name = 'HRCO'::text
          AND up_scg.is_active = true
          AND up_scg.archived_at IS NULL
        ORDER BY us_grp.created_at ASC
        LIMIT 1
      ),
      NULLIF(btrim(v.hrco_name), '')
    ) AS hrco_name,
    COALESCE(up.full_name, v.triggered_by_name) AS triggered_by_full_name,
    NULL::text AS triggered_by_role,
    vr.vacancy_type AS hc_request_type,
    vr.requested_by AS hc_request_requested_by,
    vr.requested_by_user_id AS hc_request_requested_by_user_id,
    vr.created_at AS hc_request_date_created,
    vr.no_of_slots AS hc_request_no_of_slots,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire,
    v.request_type,
    -- Occupied slots = confirmed_onboard_count + active_applicant_count
    (COALESCE(s.confirmed_onboard_count, 0::bigint) + COALESCE(s.active_applicant_count, 0::bigint))::integer AS hc_filled,
    GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric)::integer AS hc_total,
    format('%s/%s'::text, (COALESCE(s.confirmed_onboard_count, 0::bigint) + COALESCE(s.active_applicant_count, 0::bigint)), GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric)::integer) AS hc_display
   FROM public.vacancies v
     LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
     LEFT JOIN public.stores st ON st.id = v.store_id
     LEFT JOIN public.stores st_vcode ON st_vcode.id = (
       SELECT s_sub.id FROM public.stores s_sub 
        WHERE upper(s_sub.vcode) = upper(v.vcode) AND s_sub.status = 'active' 
        ORDER BY s_sub.created_at LIMIT 1
     )
     LEFT JOIN public.accounts a ON a.id = v.account_id OR (v.account_id IS NULL AND lower(trim(a.account_name)) = lower(trim(v.account)) AND lower(trim(v.account)) <> 'unknown account')
     LEFT JOIN public.accounts ast ON ast.id = COALESCE(st.account_id, st_vcode.account_id)
     LEFT JOIN public.groups g ON g.id = v.group_id
     LEFT JOIN public.groups ga ON ga.id = COALESCE(a.group_id, v.group_id)
     LEFT JOIN public.groups gst ON gst.id = COALESCE(st.group_id, st_vcode.group_id, ast.group_id)
     LEFT JOIN public.users_profile up ON up.id = v.triggered_by_user_id
     LEFT JOIN public.vacancy_requests vr ON vr.id = v.source_vacancy_request_id
     LEFT JOIN public.users_profile up_hrco ON up_hrco.id = v.hrco_user_id
     LEFT JOIN public.roles r_hrco ON r_hrco.id = up_hrco.role_id
     LEFT JOIN public.users_profile up_st_hrco ON up_st_hrco.id = COALESCE(st.hrco_user_id, st_vcode.hrco_user_id)
     LEFT JOIN public.roles r_st_hrco ON r_st_hrco.id = up_st_hrco.role_id
     LEFT JOIN public.users_profile up_a_hrco ON up_a_hrco.id = a.hrco_user_id
     LEFT JOIN public.roles r_a_hrco ON r_a_hrco.id = up_a_hrco.role_id;

-- ============================================================================
-- Section 4. Update get_web_vacancy_detail RPC
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_web_vacancy_detail(p_vacancy_id uuid)
RETURNS TABLE(
  vacancy_id uuid,
  vcode text,
  position_title text,
  employment_type text,
  vacancy_type text,
  account_id uuid,
  account_name text,
  group_id uuid,
  group_name text,
  store_id uuid,
  store_name text,
  store_branch text,
  area_name text,
  area_city text,
  province text,
  vacancy_status text,
  pipeline_status text,
  vacant_date date,
  target_fill_date date,
  aging_days integer,
  aging_bucket text,
  urgency text,
  penalty_exposure numeric,
  hrco_name text,
  recruiter_name text,
  requester_name text,
  triggered_by_name text,
  pipeline_summary jsonb,
  activity_history jsonb,
  row_capabilities jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
  v_is_active    boolean;
  v_in_scope     boolean := false;
BEGIN
  -- 1. Authentication Check
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web vacancy detail requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  -- 2. Fetch User Profile and Role Context
  SELECT up.id, r.role_name, r.role_level, up.is_active
  INTO v_profile_id, v_role_name, v_role_level, v_is_active
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  -- 3. Fail closed if unauthenticated, inactive, missing profile, or unauthorized role
  IF v_profile_id IS NULL OR NOT coalesce(v_is_active, FALSE) OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web vacancy detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF coalesce(v_role_name, '') = 'HR Personnel' THEN
    RAISE EXCEPTION 'forbidden: web vacancy detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  -- 4. Scope and Vacancy Existence Check
  SELECT EXISTS (
    SELECT 1
    FROM public.vw_vacancy_detail vd
    WHERE vd.id = p_vacancy_id
      AND coalesce(vd.is_archived, false) = false
      AND vd.archived_at IS NULL
      AND vd.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
      AND (
        v_role_level >= 90
        OR (
          vd.account = ANY (public.get_my_allowed_accounts())
          OR EXISTS (
            SELECT 1
            FROM public.user_scopes us
            WHERE us.user_id = v_profile_id
              AND us.account_id = vd.account_id
          )
          OR EXISTS (
            SELECT 1
            FROM public.user_scopes us
            JOIN public.accounts a ON a.id = vd.account_id
            WHERE us.user_id = v_profile_id
              AND us.account_id IS NULL
              AND us.group_id = a.group_id
          )
          OR EXISTS (
            SELECT 1
            FROM public.users_profile up_fallback
            JOIN public.accounts a ON a.id = vd.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (
                SELECT 1
                FROM public.user_scopes us_any
                WHERE us_any.user_id = v_profile_id
                  AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
              )
              AND (
                up_fallback.account_id = vd.account_id
                OR up_fallback.group_id = a.group_id
              )
          )
        )
      )
  ) INTO v_in_scope;

  IF NOT v_in_scope THEN
    RAISE EXCEPTION 'forbidden: vacancy is out of scope or does not exist'
      USING ERRCODE = '42501';
  END IF;

  -- 5. Return the detail record
  RETURN QUERY
  SELECT
    vd.id AS vacancy_id,
    vd.vcode,
    vd.position AS position_title,
    vd.employment_type,
    vd.vacancy_type,
    
    vd.account_id,
    vd.account AS account_name,
    vd.group_id,
    vd.group_name,
    vd.store_id,
    vd.store_name,
    vd.store_branch,
    vd.area_name,
    vd.area_city,
    vd.province,
    
    vd.status AS vacancy_status,
    vd.derived_status AS pipeline_status,
    
    vd.vacant_date,
    vd.target_fill_date,
    vd.aging_days::integer AS aging_days,
    CASE
      WHEN vd.aging_days IS NULL THEN 'unknown'
      WHEN vd.aging_days <= 7 THEN '0_7'
      WHEN vd.aging_days <= 14 THEN '8_14'
      WHEN vd.aging_days <= 30 THEN '15_30'
      ELSE '31_plus'
    END AS aging_bucket,
    
    vd.urgency_level AS urgency,
    CASE
      WHEN coalesce(v_raw.has_penalty, false)
        THEN coalesce(v_raw.penalty_amount, 0::numeric)
      ELSE 0::numeric
    END AS penalty_exposure,
    
    vd.hrco_name,
    up_rec.full_name AS recruiter_name,
    coalesce(up_req.full_name, vd.hc_request_requested_by) AS requester_name,
    vd.triggered_by_full_name AS triggered_by_name,
    
    -- Aggregated applicant/pipeline summary strictly without PII
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'applicant_id', a.id,
            'display_name', COALESCE(NULLIF(TRIM(CONCAT_WS(' ', a.first_name, a.last_name)), ''), a.full_name),
            'status_label', a.status,
            'onboard_date', a.hired_at::date,
            'updated_at', a.updated_at,
            'recruiter_name', up_a_rec.full_name,
            'deployed_by_name', up_a_dep.full_name
          )
          ORDER BY a.created_at ASC
        )
        FROM public.applicants a
        LEFT JOIN public.users_profile up_a_rec ON up_a_rec.id = COALESCE(a.created_by, v_raw.assigned_encoder_id)
        LEFT JOIN public.users_profile up_a_dep ON up_a_dep.id = a.deployed_by_user_id
        WHERE a.vacancy_vcode = vd.vcode
          AND coalesce(a.is_archived, false) = false
      ),
      '[]'::jsonb
    ) AS pipeline_summary,
    
    -- Recent vacancy audit logs/events
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'event_id', al.id,
            'event_label', CASE
              WHEN al.action = 'INSERT' THEN 'Vacancy Created'
              WHEN al.action = 'UPDATE' AND (al.new_data->>'status') IS DISTINCT FROM (al.old_data->>'status') THEN 'Status changed to ' || (al.new_data->>'status')
              WHEN al.action = 'UPDATE' AND (al.new_data->>'is_archived')::boolean = true THEN 'Vacancy Archived'
              WHEN al.action = 'DELETE' THEN 'Vacancy Deleted'
              ELSE 'Vacancy Updated'
            END,
            'event_description', CASE
              WHEN al.action = 'INSERT' THEN 'Record initialized via ' || coalesce(v_raw.source, 'system')
              WHEN al.action = 'UPDATE' AND (al.new_data->>'status') IS DISTINCT FROM (al.old_data->>'status') THEN 'Previous status: ' || coalesce(al.old_data->>'status', 'Unknown')
              ELSE 'Attributes synchronized'
            END,
            'created_at', al.timestamp,
            'profile_name', coalesce(up_al.full_name, 'System')
          )
          ORDER BY al.timestamp DESC
        )
        FROM (
          SELECT *
          FROM public.audit_logs
          WHERE record_id = vd.id
             OR (module = 'applicants' AND (new_data->>'vacancy_vcode' = vd.vcode OR old_data->>'vacancy_vcode' = vd.vcode))
          ORDER BY timestamp DESC
          LIMIT 10
        ) al
        LEFT JOIN public.users_profile up_al ON up_al.auth_user_id = al.actor_id OR up_al.id = al.actor_id
      ),
      '[]'::jsonb
    ) AS activity_history,
    
    -- Row Capabilities strictly reflecting user authority
    jsonb_build_object(
      'can_view_detail', true,
      'can_approve', (v_role_level >= 90),
      'can_update_applicant_status', (v_role_level >= 30),
      'can_request_closure', (
        v_role_level >= 30
        AND vd.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
        AND coalesce(vd.has_pending_closure, false) = false
      ),
      'has_pending_closure', coalesce(vd.has_pending_closure, false),
      'closure_request_status', vd.closure_request_status,
      'hc_filled', vd.hc_filled,
      'hc_total', vd.hc_total,
      'hc_display', vd.hc_display
    ) AS row_capabilities

  FROM public.vw_vacancy_detail vd
  JOIN public.vacancies v_raw ON v_raw.id = vd.id
  LEFT JOIN public.users_profile up_rec ON up_rec.id = v_raw.assigned_encoder_id
  LEFT JOIN public.users_profile up_req ON up_req.id = v_raw.requested_by_user_id
  WHERE vd.id = p_vacancy_id
  LIMIT 1;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_web_vacancy_detail(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_web_vacancy_detail(uuid) TO authenticated;

-- ============================================================================
-- Section 5. Idempotent Data Backfill
-- ============================================================================

-- Step 5a: Backfill public.stores missing group_id from accounts
UPDATE public.stores s
   SET group_id = a.group_id
  FROM public.accounts a
 WHERE a.id = s.account_id
   AND s.group_id IS NULL
   AND a.group_id IS NOT NULL;

-- Step 5b: Backfill public.plantilla_slots missing account_id or group_id from stores or accounts
UPDATE public.plantilla_slots s
   SET account_id = COALESCE(s.account_id, st.account_id),
       group_id   = COALESCE(s.group_id, st.group_id, a.group_id)
  FROM public.stores st
  LEFT JOIN public.accounts a ON a.id = st.account_id
 WHERE (s.store_id = st.id OR (s.store_id IS NULL AND upper(s.legacy_vcode) = upper(st.vcode)))
   AND (s.account_id IS NULL OR s.group_id IS NULL);

UPDATE public.plantilla_slots s
   SET group_id = a.group_id
  FROM public.accounts a
 WHERE a.id = s.account_id
   AND s.group_id IS NULL
   AND a.group_id IS NOT NULL;

-- Step 5c: Backfill public.vacancies missing store_id, account_id, or group_id
UPDATE public.vacancies v
   SET store_id   = COALESCE(v.store_id, st.id),
       account_id = COALESCE(v.account_id, st.account_id),
       group_id   = COALESCE(v.group_id, st.group_id)
  FROM public.stores st
 WHERE (v.store_id = st.id OR (upper(v.vcode) = upper(st.vcode) AND st.status = 'active'))
   AND (v.store_id IS NULL OR v.account_id IS NULL OR v.group_id IS NULL);

-- Step 5d: Backfill public.vacancies from plantilla_import_rows and batches
UPDATE public.vacancies v
   SET account_id = COALESCE(v.account_id, b.selected_account_id),
       group_id   = COALESCE(v.group_id, b.selected_group_id)
  FROM public.plantilla_import_rows r
  JOIN public.plantilla_import_batches b ON b.id = r.batch_id
 WHERE upper(r.vcode) = upper(v.vcode)
   AND (v.account_id IS NULL OR v.group_id IS NULL);

-- Step 5e: Inherit group_id from accounts for any remaining vacancies
UPDATE public.vacancies v
   SET group_id = a.group_id
  FROM public.accounts a
 WHERE a.id = v.account_id
   AND v.group_id IS NULL
   AND a.group_id IS NOT NULL;

-- Step 5f: Fix orphaned/unknown account name on vacancies using linked accounts.account_name
UPDATE public.vacancies v
   SET account    = a.account_name,
       updated_at = now()
  FROM public.accounts a
 WHERE a.id = v.account_id
   AND (v.account = 'Unknown Account' OR v.account IS NULL OR trim(v.account) = '');
