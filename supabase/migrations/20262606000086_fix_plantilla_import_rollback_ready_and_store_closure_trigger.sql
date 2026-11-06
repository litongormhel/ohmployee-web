-- ============================================================================
-- Migration: 20262606000086_fix_plantilla_import_rollback_ready_and_store_closure_trigger.sql
-- Prompt:    ohm#r4t7y2bn
-- Date:      2026-11-06
--
-- Purpose:
--   1. Add missing closed_at timestamptz column to public.vacancies, resolving
--      the fatal trigger error in fn_trg_store_closure_cascade_vacancies().
--   2. Re-assert fn_trg_store_closure_cascade_vacancies() on public.stores.
--   3. Update public.approve_plantilla_import_batch():
--      - Restore rollback_ready = true, committed_stores, committed_employees,
--        and approved_by_name on batch approval.
--      - Snapshot batch allocations, Phase B2 slots, and claimed vacancies into
--        public.plantilla_import_commit_snapshots for complete rollback lineage.
--   4. Update public.rollback_plantilla_import_batch() to restore/close batch-created
--      and batch-updated slots and allocations reliably.
--   5. Backfill existing approved batches with rollback_ready = true.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Schema Enhancement on public.vacancies
-- ----------------------------------------------------------------------------
ALTER TABLE public.vacancies
  ADD COLUMN IF NOT EXISTS closed_at timestamptz;

COMMENT ON COLUMN public.vacancies.closed_at IS
  'Timestamp when vacancy was closed or archived via store closure cascade or manual closure.';

-- ----------------------------------------------------------------------------
-- 2. Store Closure Cascade Trigger Function
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_trg_store_closure_cascade_vacancies()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_slot record;
  v_actor uuid;
BEGIN
  -- Fires when store deletion/closure is approved:
  -- Transition to status = 'archived', is_active = false, or from deletion_requested to archived
  IF (NEW.status = 'archived' AND OLD.status <> 'archived')
     OR (NEW.is_active = false AND OLD.is_active = true)
     OR (OLD.is_deletion_requested = true AND NEW.is_deletion_requested = false AND NEW.status = 'archived')
  THEN
    BEGIN
      v_actor := public.get_current_profile_id();
    EXCEPTION WHEN OTHERS THEN
      v_actor := NULL;
    END;

    -- Close open/pipeline plantilla slots for this store via fn_set_slot_status (ADR-001 Rule 1)
    FOR v_slot IN
      SELECT ps.id AS slot_id
        FROM public.plantilla_slots ps
       WHERE ps.store_id = NEW.id
         AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
    LOOP
      BEGIN
        PERFORM public.fn_set_slot_status(
          p_slot_id      => v_slot.slot_id,
          p_new_status   => 'closed',
          p_reason_code  => 'STORE_CLOSED',
          p_performed_by => v_actor
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'fn_trg_store_closure_cascade_vacancies: slot close failed for slot_id=% err=%',
          v_slot.slot_id, SQLERRM;
      END;
    END LOOP;

    -- Cascade mark associated vacancies as is_archived = true and status = 'Closed'
    UPDATE public.vacancies
       SET status = 'Closed',
           is_archived = true,
           archived_at = COALESCE(archived_at, NOW()),
           closed_at = COALESCE(closed_at, NOW()),
           updated_at = NOW(),
           updated_by = COALESCE(v_actor, updated_by)
     WHERE store_id = NEW.id
       AND (COALESCE(is_archived, false) = false OR status <> 'Closed');

  END IF;

  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_store_closure_cascade_vacancies'
  ) THEN
    CREATE TRIGGER trg_store_closure_cascade_vacancies
      AFTER UPDATE OF status, is_active, is_deletion_requested ON public.stores
      FOR EACH ROW
      EXECUTE FUNCTION public.fn_trg_store_closure_cascade_vacancies();
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Update public.approve_plantilla_import_batch
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_plantilla_import_batch(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '60s'
AS $function$
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
  v_old_slot_snap  jsonb;
  v_new_alloc_id   uuid;
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

  -- Pre-commit guard 2: Committable includes valid and flagged rows with vcode
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

      -- Snapshot existing active allocations prior to deactivation for rollback restoration
      INSERT INTO public.plantilla_import_commit_snapshots
        (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
      SELECT
        p_batch_id, 'allocation', a.id, 'update', to_jsonb(a.*), v_uid
        FROM public.employee_store_allocations a
       WHERE a.employee_no = v_emp_rec.employee_no
         AND a.is_active
         AND a.account_id = v_batch.selected_account_id;

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
        ) RETURNING id INTO v_new_alloc_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'allocation', v_new_alloc_id, 'insert', NULL, v_uid);

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
            -- Capture snapshot before claiming pre-existing slot
            SELECT to_jsonb(ps.*) INTO v_old_slot_snap
              FROM public.plantilla_slots ps
             WHERE id = v_target_slot_id;

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

            INSERT INTO public.plantilla_import_commit_snapshots
              (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
            VALUES (p_batch_id, 'slot', v_target_slot_id, 'update', v_old_slot_snap, v_uid);

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

            INSERT INTO public.plantilla_import_commit_snapshots
              (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
            VALUES (p_batch_id, 'slot', v_target_slot_id, 'insert', NULL, v_uid);
          END IF;
        END IF;

      END LOOP;

    END LOOP;

    -- Update batch status with ADR-002 rollback governance metadata
    v_approved_timestamp := clock_timestamp();
    UPDATE public.plantilla_import_batches
       SET status              = 'approved',
           approved_by         = v_uid,
           approved_at         = v_approved_timestamp,
           approved_by_name    = v_user_name,
           rejection_reason    = NULL,
           commit_error        = NULL,
           committed_stores    = v_stores_done,
           committed_employees = v_employees_done,
           stores_created      = v_stores_done,
           employees_created   = v_employees_done,
           allocations_created = v_alloc_done,
           rollback_ready      = true,
           updated_at          = v_approved_timestamp
     WHERE id = p_batch_id;

    RETURN jsonb_build_object(
      'success', true,
      'batch_id', p_batch_id,
      'status', 'approved',
      'stores_processed', v_stores_done,
      'employees_processed', v_employees_done,
      'allocations_created', v_alloc_done,
      'vacant_slots_created', v_vacant_slots,
      'rollback_ready', true,
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
$function$;

-- ----------------------------------------------------------------------------
-- 4. Update public.rollback_plantilla_import_batch
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rollback_plantilla_import_batch(p_batch_id uuid, p_reason text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_actor uuid := public.get_current_profile_id();
  v_batch public.plantilla_import_batches%ROWTYPE;
  v_reason text := NULLIF(trim(COALESCE(p_reason, '')), '');
  v_archive_reason text;

  v_plantilla_restored      int := 0;
  v_plantilla_archived      int := 0;
  v_stores_restored         int := 0;
  v_stores_deactivated      int := 0;
  v_allocations_restored    int := 0;
  v_allocations_deactivated int := 0;
  v_slots_closed            int := 0;
  v_slots_restored          int := 0;
  v_roving_groups_archived  int := 0;
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
        ) pir
        JOIN public.employee_store_allocations a
          ON upper(trim(a.employee_no)) = upper(trim(pir.employee_no))
       WHERE a.is_active
         AND a.source_import_batch_id IS DISTINCT FROM p_batch_id
    ) THEN
      RAISE EXCEPTION 'ROLLBACK_UNSAFE: allocations have been modified after batch %',
        p_batch_id USING ERRCODE = '40001';
    END IF;

    -- Batch-created allocations: deactivate
    UPDATE public.employee_store_allocations a
       SET is_active   = false
      FROM public.plantilla_import_commit_snapshots s
     WHERE s.batch_id = p_batch_id
       AND s.entity_type = 'allocation'
       AND s.action = 'insert'
       AND s.entity_id = a.id
       AND a.source_import_batch_id = p_batch_id
       AND a.is_active;
    GET DIAGNOSTICS v_allocations_deactivated = ROW_COUNT;

    -- Batch-updated allocations: restore previous snapshot
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
       SET is_active   = (snap.r).is_active,
           store_id    = (snap.r).store_id,
           account_id  = (snap.r).account_id,
           group_id    = (snap.r).group_id,
           vcode       = (snap.r).vcode,
           employee_no = (snap.r).employee_no
      FROM snap
     WHERE a.id = snap.entity_id;
    GET DIAGNOSTICS v_allocations_restored = ROW_COUNT;

    -- Batch-created plantilla rows: soft archive, never hard delete.
    UPDATE public.plantilla p
       SET is_archived   = true,
           archived_at   = now(),
           archived_by   = v_actor,
           archive_reason = v_archive_reason,
           status        = 'Inactive',
           updated_at    = now(),
           updated_by    = v_actor
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
       SET employee_name                   = (snap.r).employee_name,
           employee_no                     = (snap.r).employee_no,
           account                         = (snap.r).account,
           status                          = (snap.r).status,
           emploc_no                       = (snap.r).emploc_no,
           vcode                           = (snap.r).vcode,
           position                        = (snap.r).position,
           created_at                      = (snap.r).created_at,
           hr_emploc_id                    = (snap.r).hr_emploc_id,
           vacancy_id                      = (snap.r).vacancy_id,
           vacancy_code_snapshot           = (snap.r).vacancy_code_snapshot,
           employee_name_snapshot          = (snap.r).employee_name_snapshot,
           account_id                      = (snap.r).account_id,
           chain_id                        = (snap.r).chain_id,
           store_id                        = (snap.r).store_id,
           province_id                     = (snap.r).province_id,
           area_name_snapshot              = (snap.r).area_name_snapshot,
           hrco_user_id_snapshot           = (snap.r).hrco_user_id_snapshot,
           om_user_id_snapshot             = (snap.r).om_user_id_snapshot,
           atl_user_id_snapshot            = (snap.r).atl_user_id_snapshot,
           position_id                     = (snap.r).position_id,
           rest_day                        = (snap.r).rest_day,
           resignation_date                = (snap.r).resignation_date,
           remarks                         = (snap.r).remarks,
           moved_by_user_id                = (snap.r).moved_by_user_id,
           created_by                      = (snap.r).created_by,
           updated_at                      = (snap.r).updated_at,
           updated_by                      = (snap.r).updated_by,
           store_name                      = (snap.r).store_name,
           area                            = (snap.r).area,
           rate                            = (snap.r).rate,
           schedule                        = (snap.r).schedule,
           deployment_type                 = (snap.r).deployment_type,
           has_penalty                     = (snap.r).has_penalty,
           date_hired                      = (snap.r).date_hired,
           coordinator                     = (snap.r).coordinator,
           hrco_name                       = (snap.r).hrco_name,
           last_name                       = (snap.r).last_name,
           first_name                      = (snap.r).first_name,
           middle_name                     = (snap.r).middle_name,
           date_of_separation              = (snap.r).date_of_separation,
           separation_status               = (snap.r).separation_status,
           tagged_at                       = (snap.r).tagged_at,
           inactive_at                     = (snap.r).inactive_at,
           inactive_by                     = (snap.r).inactive_by,
           for_deactivation_at             = (snap.r).for_deactivation_at,
           for_deactivation_by             = (snap.r).for_deactivation_by,
           deactivated_at                  = (snap.r).deactivated_at,
           deactivated_by                  = (snap.r).deactivated_by,
           deactivated_visible_until       = (snap.r).deactivated_visible_until,
           last_mika_synced_at             = (snap.r).last_mika_synced_at,
           last_mika_synced_by             = (snap.r).last_mika_synced_by,
           source_headcount_request_id     = (snap.r).source_headcount_request_id,
           is_deleted                      = (snap.r).is_deleted,
           over_headcount                  = (snap.r).over_headcount,
           deactivation_reason             = (snap.r).deactivation_reason,
           deletion_requested_at           = (snap.r).deletion_requested_at,
           deletion_requested_by           = (snap.r).deletion_requested_by,
           deletion_reason                 = (snap.r).deletion_reason,
           deletion_remarks                = (snap.r).deletion_remarks,
           deletion_approved_at            = (snap.r).deletion_approved_at,
           deletion_approved_by            = (snap.r).deletion_approved_by,
           sss_no                          = (snap.r).sss_no,
           philhealth_no                   = (snap.r).philhealth_no,
           pagibig_no                      = (snap.r).pagibig_no,
           atm_no                          = (snap.r).atm_no,
           civil_status                    = (snap.r).civil_status,
           date_of_birth                   = (snap.r).date_of_birth,
           transferred_from_store_id       = (snap.r).transferred_from_store_id,
           last_transfer_at                = (snap.r).last_transfer_at,
           last_transfer_by                = (snap.r).last_transfer_by,
           inactive_visible_until          = (snap.r).inactive_visible_until,
           is_archived                     = (snap.r).is_archived,
           archived_at                     = (snap.r).archived_at,
           archived_by                     = (snap.r).archived_by,
           archive_reason                  = (snap.r).archive_reason,
           restored_at                     = (snap.r).restored_at,
           restored_by                     = (snap.r).restored_by,
           source_baseline_import_batch_id = (snap.r).source_baseline_import_batch_id,
           roving_assignment_id            = (snap.r).roving_assignment_id,
           is_pool_employee                = (snap.r).is_pool_employee
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
       SET account_id       = (snap.r).account_id,
           store_name       = (snap.r).store_name,
           store_branch     = (snap.r).store_branch,
           area_city        = (snap.r).area_city,
           province         = (snap.r).province,
           is_active        = (snap.r).is_active,
           created_at       = (snap.r).created_at,
           updated_at       = (snap.r).updated_at,
           group_id         = (snap.r).group_id,
           hrco_user_id     = (snap.r).hrco_user_id,
           om_user_id       = (snap.r).om_user_id,
           vcode            = (snap.r).vcode,
           area_province    = (snap.r).area_province,
           with_penalty     = (snap.r).with_penalty,
           status           = (snap.r).status,
           created_by       = (snap.r).created_by,
           updated_by       = (snap.r).updated_by,
           approved_by      = (snap.r).approved_by,
           approved_at      = (snap.r).approved_at,
           source_import_id = (snap.r).source_import_id,
           employment_type  = (snap.r).employment_type
      FROM snap
     WHERE st.id = snap.entity_id
       AND st.source_import_id = p_batch_id;
    GET DIAGNOSTICS v_stores_restored = ROW_COUNT;

    -- Batch-created stores: deactivate only when no active plantilla/allocation remains.
    UPDATE public.stores st
       SET is_active   = false,
           status      = 'archived',
           updated_at  = now(),
           updated_by  = v_actor
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

    -- Batch-created plantilla slots: close if open or occupied by rolled-back occupant
    UPDATE public.plantilla_slots ps
       SET slot_status                 = 'closed',
           closure_reason_code         = 'IMPORT_ROLLBACK',
           current_occupant_plantilla_id = NULL,
           closed_at                   = now(),
           updated_at                  = now(),
           updated_by                  = v_actor
      FROM public.plantilla_import_commit_snapshots s
     WHERE s.batch_id = p_batch_id
       AND s.entity_type = 'slot'
       AND s.action = 'insert'
       AND s.entity_id = ps.id;
    GET DIAGNOSTICS v_slots_closed = ROW_COUNT;

    -- Batch-updated plantilla slots (claimed open slots): restore previous snapshot
    WITH snap AS (
      SELECT s.entity_id, jsonb_populate_record(NULL::public.plantilla_slots, s.previous_snapshot) AS r
        FROM public.plantilla_import_commit_snapshots s
       WHERE s.batch_id = p_batch_id
         AND s.entity_type = 'slot'
         AND s.action = 'update'
         AND s.previous_snapshot IS NOT NULL
    )
    UPDATE public.plantilla_slots ps
       SET slot_status                   = (snap.r).slot_status,
           current_occupant_plantilla_id = (snap.r).current_occupant_plantilla_id,
           is_roving                     = (snap.r).is_roving,
           employment_type               = (snap.r).employment_type,
           position                      = (snap.r).position,
           updated_at                    = now(),
           updated_by                    = v_actor
      FROM snap
     WHERE ps.id = snap.entity_id;
    GET DIAGNOSTICS v_slots_restored = ROW_COUNT;

    -- Batch-created vacancies: archive if still open
    UPDATE public.vacancies v
       SET status     = 'Archived',
           is_archived = true,
           deleted_at = now(),
           closed_at  = now(),
           updated_at = now(),
           updated_by = v_actor
      FROM public.plantilla_import_commit_snapshots s
     WHERE s.batch_id = p_batch_id
       AND s.entity_type = 'vacancy'
       AND s.action = 'insert'
       AND s.entity_id = v.id
       AND v.status = 'Open';

    -- Batch-updated vacancies: restore previous snapshot
    WITH snap AS (
      SELECT s.entity_id, jsonb_populate_record(NULL::public.vacancies, s.previous_snapshot) AS r
        FROM public.plantilla_import_commit_snapshots s
       WHERE s.batch_id = p_batch_id
         AND s.entity_type = 'vacancy'
         AND s.action = 'update'
         AND s.previous_snapshot IS NOT NULL
    )
    UPDATE public.vacancies v
       SET status             = (snap.r).status,
           store_id           = (snap.r).store_id,
           store_name         = (snap.r).store_name,
           position           = (snap.r).position,
           required_headcount = (snap.r).required_headcount,
           employment_type    = (snap.r).employment_type,
           is_archived        = (snap.r).is_archived,
           deleted_at         = (snap.r).deleted_at,
           updated_at         = now(),
           updated_by         = v_actor
      FROM snap
     WHERE v.id = snap.entity_id;

    -- Roving groups created by this batch: close them if no active allocations remain.
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

    -- Mark rollback success.
    UPDATE public.plantilla_import_batches
       SET status               = 'rolled_back',
           rolled_back_by       = v_uid,
           rolled_back_at       = now(),
           rollback_reason      = v_reason,
           rollback_error_detail = NULL,
           updated_at           = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, old_data, new_data)
    VALUES (
      v_uid,
      'plantilla_import_batches',
      'UPDATE',
      p_batch_id,
      jsonb_build_object('status', 'approved'),
      jsonb_build_object(
        'status',                  'rolled_back',
        'batch_id',                p_batch_id,
        'plantilla_restored',      v_plantilla_restored,
        'plantilla_archived',      v_plantilla_archived,
        'stores_restored',         v_stores_restored,
        'stores_deactivated',      v_stores_deactivated,
        'allocations_restored',    v_allocations_restored,
        'allocations_deactivated', v_allocations_deactivated,
        'slots_closed',            v_slots_closed,
        'slots_restored',          v_slots_restored,
        'roving_groups_archived',  v_roving_groups_archived,
        'reason',                  v_reason
      )
    );

    RETURN jsonb_build_object(
      'status',                  'rolled_back',
      'batch_id',                p_batch_id,
      'plantilla_restored',      v_plantilla_restored,
      'plantilla_archived',      v_plantilla_archived,
      'stores_restored',         v_stores_restored,
      'stores_deactivated',      v_stores_deactivated,
      'allocations_restored',    v_allocations_restored,
      'allocations_deactivated', v_allocations_deactivated,
      'slots_closed',            v_slots_closed,
      'slots_restored',          v_slots_restored,
      'reason',                  v_reason
    );

  EXCEPTION WHEN OTHERS THEN
    UPDATE public.plantilla_import_batches
       SET status               = 'rollback_failed',
           rollback_error_detail = format('[%s] %s', SQLSTATE, SQLERRM),
           rollback_reason      = v_reason,
           updated_at           = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, old_data, new_data)
    VALUES (
      v_uid,
      'plantilla_import_batches',
      'UPDATE',
      p_batch_id,
      jsonb_build_object('status', 'approved'),
      jsonb_build_object(
        'status',   'rollback_failed',
        'batch_id', p_batch_id,
        'error',    format('[%s] %s', SQLSTATE, SQLERRM),
        'reason',   v_reason
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
$function$;

-- ----------------------------------------------------------------------------
-- 5. Backfill Existing Approved Batches with rollback_ready = true
-- ----------------------------------------------------------------------------
UPDATE public.plantilla_import_batches
   SET rollback_ready = true
 WHERE status = 'approved' AND rollback_ready = false;
