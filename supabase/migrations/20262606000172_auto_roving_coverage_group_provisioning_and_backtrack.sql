-- Migration: 20262606000172_auto_roving_coverage_group_provisioning_and_backtrack.sql
-- Description:
-- 1. ADR-002 Invariants 3 & 4: Universal Automatic Coverage Group (CGCODE) Provisioning.
-- 2. Backtrack historical multi-store roving personnel (from June baseline imports to present)
--    without an assigned Coverage Group: auto-mint CGCODE, register coverage_groups,
--    coverage_group_stores (with anchor and hc_share), coverage_slots, and link
--    plantilla.coverage_group_id and employee_store_allocations.roving_group_id.
-- 3. Update public.approve_plantilla_import_batch() so all future imports automatically
--    provision or bind roving personnel to active Coverage Groups.

BEGIN;

-- ============================================================================
-- Section 0: Ensure trigger handles both INSERT and UPDATE for roving_group_id
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_ensure_import_roving_group_for_allocation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.roving_group_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.import_roving_groups WHERE id = NEW.roving_group_id
    ) THEN
      INSERT INTO public.import_roving_groups (
        id, employee_no, account_id, group_id, account_name, label,
        active_store_count, filled_hc_per_store, source_import_batch_id,
        plantilla_id, created_at, created_by, updated_at, archived_at
      )
      SELECT
        NEW.roving_group_id,
        NEW.employee_no,
        NEW.account_id,
        NEW.group_id,
        (SELECT account_name FROM public.accounts WHERE id = NEW.account_id),
        'CG-' || NEW.employee_no,
        COALESCE(NEW.active_store_count, 2),
        COALESCE(NEW.filled_hc, 0.5),
        NEW.source_import_batch_id,
        NEW.plantilla_id,
        now(),
        NEW.created_by,
        now(),
        now()
      ON CONFLICT (id) DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ensure_import_roving_group_for_allocation ON public.employee_store_allocations;

CREATE TRIGGER trg_ensure_import_roving_group_for_allocation
BEFORE INSERT OR UPDATE ON public.employee_store_allocations
FOR EACH ROW
EXECUTE FUNCTION public.fn_ensure_import_roving_group_for_allocation();

-- ============================================================================
-- Section 1: Historical Data Backtrack
-- ============================================================================
DO $backtrack$
DECLARE
  v_rec record;
  v_store_ids uuid[];
  v_store_count int;
  v_group_id uuid;
  v_cgcode text;
  v_pos_id uuid;
  v_anchor_id uuid;
  v_sid uuid;
  v_slot_id uuid;
  v_slot_ord int;
  v_actor uuid;
  v_backtracked_count int := 0;
BEGIN
  -- Resolve actor for audit fields
  SELECT id INTO v_actor
    FROM public.users_profile
   WHERE is_active = true
   ORDER BY (role_id IN (SELECT id FROM public.roles WHERE role_name = 'Super Admin')) DESC, created_at ASC
   LIMIT 1;

  FOR v_rec IN
    SELECT
      p.id AS plantilla_id,
      p.employee_no,
      p.employee_name,
      p.account_id,
      p.position,
      p.civil_status,
      p.area,
      p.date_hired,
      p.store_id AS primary_store_id
    FROM public.plantilla p
    WHERE p.is_deleted = false
      AND p.status IN ('Active', 'On Leave', 'Pending Deactivation', 'For Deactivation', 'Floating')
      AND p.coverage_group_id IS NULL
      AND (
        lower(COALESCE(p.deployment_type, '')) = 'roving'
        OR (
          SELECT count(DISTINCT s_sub.store_id)
          FROM (
            SELECT esa.store_id
            FROM public.employee_store_allocations esa
            WHERE esa.plantilla_id = p.id AND esa.store_id IS NOT NULL
            UNION
            SELECT s.id AS store_id
            FROM public.plantilla_store_links psl
            JOIN public.stores s ON upper(s.vcode) = upper(psl.vcode) AND s.account_id = p.account_id
            WHERE psl.plantilla_id = p.id AND psl.deleted_at IS NULL
            UNION
            SELECT p.store_id WHERE p.store_id IS NOT NULL
          ) s_sub
        ) >= 2
      )
    ORDER BY p.account_id, p.employee_name
  LOOP
    -- Collect distinct stores belonging to the employee's account
    SELECT array_agg(DISTINCT s_sub.store_id ORDER BY s_sub.store_id)
      INTO v_store_ids
      FROM (
        SELECT esa.store_id
        FROM public.employee_store_allocations esa
        JOIN public.stores s ON s.id = esa.store_id AND s.account_id = v_rec.account_id
        WHERE esa.plantilla_id = v_rec.plantilla_id
        UNION
        SELECT s.id AS store_id
        FROM public.plantilla_store_links psl
        JOIN public.stores s ON upper(s.vcode) = upper(psl.vcode) AND s.account_id = v_rec.account_id
        WHERE psl.plantilla_id = v_rec.plantilla_id AND psl.deleted_at IS NULL
        UNION
        SELECT s.id AS store_id
        FROM public.stores s
        WHERE s.id = v_rec.primary_store_id AND s.account_id = v_rec.account_id
      ) s_sub;

    v_store_count := COALESCE(array_length(v_store_ids, 1), 0);

    -- Only proceed if multi-store footprint (N >= 2)
    IF v_store_count >= 2 THEN
      -- Step A: Check if an active coverage group with identical member stores already exists
      v_group_id := NULL;
      SELECT cgs.coverage_group_id
        INTO v_group_id
        FROM public.coverage_group_stores cgs
        JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
       WHERE cg.account_id = v_rec.account_id
         AND cg.archived_at IS NULL
         AND lower(COALESCE(cg.status, '')) <> 'archived'
         AND cgs.archived_at IS NULL
       GROUP BY cgs.coverage_group_id
      HAVING array_agg(cgs.store_id ORDER BY cgs.store_id) = v_store_ids
       LIMIT 1;

      -- Step B: If not found, create new coverage group
      IF v_group_id IS NOT NULL THEN
        UPDATE public.coverage_groups
           SET required_headcount = GREATEST(required_headcount, (
                 SELECT count(*) FROM public.coverage_slots WHERE coverage_group_id = v_group_id
               ) + 1),
               updated_at = now()
         WHERE id = v_group_id;
      ELSE
        v_cgcode := public.fn_generate_cgcode_for_account(v_rec.account_id);
        v_group_id := gen_random_uuid();

        SELECT id INTO v_pos_id
          FROM public.positions
         WHERE lower(position_name) = lower(v_rec.position)
         LIMIT 1;

        IF v_pos_id IS NULL THEN
          SELECT position_id INTO v_pos_id
            FROM public.v_account_position_options
           WHERE account_id = v_rec.account_id
           LIMIT 1;
        END IF;

        INSERT INTO public.coverage_groups (
          id, coverage_code, account_id, position_id, employment_type,
          required_headcount, status, area_name, created_by, created_at
        ) VALUES (
          v_group_id, v_cgcode, v_rec.account_id, v_pos_id,
          COALESCE(v_rec.civil_status, 'Regular'), 1, 'open',
          v_rec.area, v_actor, now()
        );

        -- Pick anchor store
        v_anchor_id := COALESCE(v_rec.primary_store_id, v_store_ids[1]);
        IF NOT (v_anchor_id = ANY(v_store_ids)) THEN
          v_anchor_id := v_store_ids[1];
        END IF;

        FOREACH v_sid IN ARRAY v_store_ids LOOP
          INSERT INTO public.coverage_group_stores (
            coverage_group_id, store_id, is_anchor, added_by, added_at, hc_share
          ) VALUES (
            v_group_id, v_sid, (v_sid = v_anchor_id),
            v_actor, now(), round(1.0 / v_store_count, 4)
          ) ON CONFLICT (coverage_group_id, store_id) WHERE (archived_at IS NULL)
          DO UPDATE SET hc_share = round(1.0 / v_store_count, 4);
        END LOOP;
      END IF;

      -- Step C: Provision slot in coverage_slots
      v_slot_id := NULL;
      SELECT id INTO v_slot_id
        FROM public.coverage_slots
       WHERE coverage_group_id = v_group_id
         AND current_occupant_plantilla_id = v_rec.plantilla_id
       LIMIT 1;

      IF v_slot_id IS NULL THEN
        SELECT COALESCE(MAX(slot_ordinal), 0) + 1 INTO v_slot_ord
          FROM public.coverage_slots
         WHERE coverage_group_id = v_group_id;

        INSERT INTO public.coverage_slots (
          id, coverage_group_id, slot_ordinal, slot_status,
          current_occupant_plantilla_id, created_at, updated_at
        ) VALUES (
          gen_random_uuid(), v_group_id, v_slot_ord, 'active',
          v_rec.plantilla_id, now(), now()
        ) RETURNING id INTO v_slot_id;
      END IF;

      -- Step D: Update plantilla row (clearing legacy roving_assignment_id per plantilla_roving_coverage_mutex_chk)
      UPDATE public.plantilla
         SET deployment_type = 'Roving',
             coverage_group_id = v_group_id,
             coverage_slot_id = v_slot_id,
             roving_assignment_id = NULL,
             updated_at = now()
       WHERE id = v_rec.plantilla_id;

      -- Step E: Reconcile employee_store_allocations
      UPDATE public.employee_store_allocations
         SET roving_group_id = v_group_id,
             is_active = true,
             filled_hc = round(1.0 / v_store_count, 4),
             active_store_count = v_store_count
       WHERE plantilla_id = v_rec.plantilla_id
         AND store_id = ANY(v_store_ids);

      -- Ensure all member stores have an allocation row
      FOREACH v_sid IN ARRAY v_store_ids LOOP
        IF NOT EXISTS (
          SELECT 1 FROM public.employee_store_allocations
           WHERE plantilla_id = v_rec.plantilla_id AND store_id = v_sid
        ) THEN
          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            created_by, created_at
          )
          SELECT
            v_rec.plantilla_id, v_rec.employee_no, v_group_id,
            s.id, s.vcode, s.store_name,
            v_rec.account_id, s.group_id,
            round(1.0 / v_store_count, 4), v_store_count,
            COALESCE(v_rec.date_hired, CURRENT_DATE), true,
            v_actor, now()
          FROM public.stores s
          WHERE s.id = v_sid;
        END IF;

        -- Ensure plantilla_store_links has active link (when vcode exists)
        INSERT INTO public.plantilla_store_links (
          plantilla_id, vcode, store_name, account, status, linked_at
        )
        SELECT
          v_rec.plantilla_id, s.vcode, s.store_name, a.account_name, 'Active', now()
        FROM public.stores s
        JOIN public.accounts a ON a.id = s.account_id
        WHERE s.id = v_sid AND s.vcode IS NOT NULL
        ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL)
        DO UPDATE SET
          store_name = EXCLUDED.store_name,
          account = EXCLUDED.account,
          status = 'Active';
      END LOOP;

      v_backtracked_count := v_backtracked_count + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'Backtrack completed: % roving employees provisioned with Coverage Groups', v_backtracked_count;
END $backtrack$;


-- ============================================================================
-- Section 2: Update public.approve_plantilla_import_batch
-- ============================================================================
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

  -- Coverage group auto-provisioning locals (ADR-002 Invariants 3 & 4)
  v_cov_group_id    uuid;
  v_cov_cgcode      text;
  v_cov_slot_id     uuid;
  v_cov_slot_ord    int;
  v_cov_pos_id      uuid;
  v_cov_anchor_id   uuid;
  v_cov_store_ids   uuid[];
  v_cov_s_id        uuid;

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
    -- ========================================================================
    -- Phase A: Store upsert for all committable rows (valid + flagged)
    -- ========================================================================
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
       WHERE upper(s.vcode) = upper(v_srow.vcode)
         AND (s.status = 'active' OR (s.account_id = v_batch.selected_account_id AND s.status = 'archived'))
       ORDER BY CASE WHEN s.status = 'active' THEN 1 ELSE 2 END, s.created_at LIMIT 1;

      IF v_old_store_snap IS NULL THEN
        INSERT INTO public.stores (
          vcode, store_name, mother_account, area_province, province, area_city,
          employment_type, with_penalty, schedule_days, schedule_time,
          group_id, account_id, status, hrco_user_id,
          created_by, updated_by, approved_by, approved_at, source_import_id
        ) VALUES (
          v_srow.vcode, v_srow.store_name, v_srow.mother_account,
          v_srow.area_province, v_srow.area_province, v_srow.area_city,
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
           SET store_name       = v_srow.store_name,
               mother_account   = COALESCE(v_srow.mother_account, mother_account),
               area_province    = COALESCE(v_srow.area_province, area_province),
               province         = COALESCE(v_srow.area_province, province),
               area_city        = COALESCE(v_srow.area_city, area_city),
               employment_type  = COALESCE(v_srow.employment_type, employment_type),
               with_penalty     = COALESCE(v_pen_bool, with_penalty),
               schedule_days    = COALESCE(v_srow.schedule_days, schedule_days),
               schedule_time    = COALESCE(v_srow.schedule_time, schedule_time),
               account_id       = COALESCE(stores.account_id, v_batch.selected_account_id),
               group_id         = COALESCE(stores.group_id, v_batch.selected_group_id),
               hrco_user_id     = COALESCE(v_acct_hrco_id, hrco_user_id),
               status           = 'active',
               is_active        = true,
               is_archived      = false,
               archived_at      = NULL,
               updated_at       = now(),
               updated_by       = v_uid,
               approved_by      = v_uid,
               approved_at      = now(),
               source_import_id = p_batch_id
         WHERE id = v_existing_store_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_existing_store_id, 'update', v_old_store_snap, v_uid);
      END IF;

      v_stores_done := v_stores_done + 1;
    END LOOP;

    -- ========================================================================
    -- Phase B1: Vacant Store Slot Creation (committable rows where employee_no IS NULL)
    -- ========================================================================
    FOR v_vrow IN
      SELECT vcode, store_name, position, area_province, area_city, id AS row_id
        FROM public.plantilla_import_rows pir
       WHERE pir.batch_id = p_batch_id
         AND pir.validation_status IN ('valid', 'flagged')
         AND pir.employee_no IS NULL
         AND pir.vcode IS NOT NULL
       ORDER BY pir.vcode, pir.row_number
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

    -- ========================================================================
    -- Phase B2: Assigned Employee Upsert & Slot Provisioning (valid + flagged)
    -- Enforces LAST-ROW-WINS persistence for coalesced demographic, compensation & rest-day fields
    -- Enforces ADR-002 Invariants 3 & 4: Universal Automatic Coverage Group Provisioning
    -- ========================================================================
    FOR v_emp_rec IN
      SELECT
        employee_no,
        count(DISTINCT vcode)                                                       AS store_count,
        (array_agg(last_name   ORDER BY row_number DESC))[1]                        AS last_name,
        (array_agg(first_name  ORDER BY row_number DESC))[1]                        AS first_name,
        (array_agg(middle_name ORDER BY row_number DESC))[1]                        AS middle_name,
        (array_agg(position    ORDER BY row_number DESC) FILTER (WHERE position IS NOT NULL))[1] AS position,
        (array_agg(vcode       ORDER BY row_number) FILTER (WHERE vcode IS NOT NULL))[1] AS primary_vcode,
        (array_agg(store_name  ORDER BY row_number) FILTER (WHERE store_name IS NOT NULL))[1] AS primary_store_name,
        (array_agg(mother_account ORDER BY row_number) FILTER (WHERE mother_account IS NOT NULL))[1] AS mother_account,
        (array_agg(area_province ORDER BY row_number) FILTER (WHERE area_province IS NOT NULL))[1] AS area_province,
        (array_agg(area_city ORDER BY row_number) FILTER (WHERE area_city IS NOT NULL))[1] AS area_city,
        (array_agg(civil_status ORDER BY row_number DESC) FILTER (WHERE civil_status IS NOT NULL))[1] AS civil_status,
        (array_agg(rate_raw ORDER BY row_number DESC) FILTER (WHERE rate_raw IS NOT NULL))[1] AS rate_raw,
        (array_agg(birthdate_raw ORDER BY row_number DESC) FILTER (WHERE birthdate_raw IS NOT NULL))[1] AS birthdate_raw,
        (array_agg(date_hired_raw ORDER BY row_number DESC) FILTER (WHERE date_hired_raw IS NOT NULL))[1] AS date_hired_raw,
        (array_agg(contact_raw ORDER BY row_number DESC) FILTER (WHERE contact_raw IS NOT NULL))[1] AS contact_raw,
        (array_agg(address_raw ORDER BY row_number DESC) FILTER (WHERE address_raw IS NOT NULL))[1] AS address_raw,
        (array_agg(schedule_days ORDER BY row_number DESC) FILTER (WHERE schedule_days IS NOT NULL))[1] AS schedule_days,
        (array_agg(schedule_time ORDER BY row_number DESC) FILTER (WHERE schedule_time IS NOT NULL))[1] AS schedule_time,
        (array_agg(dayoff_raw ORDER BY row_number DESC) FILTER (WHERE dayoff_raw IS NOT NULL))[1] AS dayoff_raw,
        (array_agg(coordinator_raw ORDER BY row_number DESC) FILTER (WHERE coordinator_raw IS NOT NULL))[1] AS coordinator_raw,
        bool_or(needs_hrco) AS needs_hrco_agg,
        (array_agg(resolved_hrco_user_id ORDER BY row_number DESC) FILTER (WHERE resolved_hrco_user_id IS NOT NULL))[1] AS hrco_id
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

      -- Plantilla lookup (active employees only; rolled-back inactive rows are NOT reused as update targets)
      v_plantilla_id := NULL;
      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no
         AND is_deleted = false
         AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation','Floating')
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
        -- Update existing plantilla record with inherited fields (last-row-wins)
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

      -- ======================================================================
      -- Coverage Group Auto-Provisioning (ADR-002 Invariants 3 & 4)
      -- ======================================================================
      v_cov_group_id := NULL;
      v_cov_slot_id  := NULL;

      IF v_store_cnt > 1 THEN
        -- Collect distinct active stores for this roving employee in the batch account
        SELECT array_agg(DISTINCT s.id ORDER BY s.id)
          INTO v_cov_store_ids
          FROM public.plantilla_import_rows pir
          JOIN public.stores s ON upper(s.vcode) = upper(pir.vcode) AND s.status = 'active'
         WHERE pir.batch_id = p_batch_id
           AND pir.employee_no = v_emp_rec.employee_no
           AND pir.validation_status IN ('valid', 'flagged')
           AND s.account_id = v_batch.selected_account_id;

        IF COALESCE(array_length(v_cov_store_ids, 1), 0) > 1 THEN
          -- Check if an active coverage group with identical member stores already exists
          SELECT cgs.coverage_group_id
            INTO v_cov_group_id
            FROM public.coverage_group_stores cgs
            JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
           WHERE cg.account_id = v_batch.selected_account_id
             AND cg.archived_at IS NULL
             AND lower(COALESCE(cg.status, '')) <> 'archived'
             AND cgs.archived_at IS NULL
           GROUP BY cgs.coverage_group_id
          HAVING array_agg(cgs.store_id ORDER BY cgs.store_id) = v_cov_store_ids
           LIMIT 1;

          IF v_cov_group_id IS NOT NULL THEN
            UPDATE public.coverage_groups
               SET required_headcount = GREATEST(required_headcount, (
                     SELECT count(*) FROM public.coverage_slots WHERE coverage_group_id = v_cov_group_id
                   ) + 1),
                   updated_at = now()
             WHERE id = v_cov_group_id;
          ELSE
            v_cov_cgcode   := public.fn_generate_cgcode_for_account(v_batch.selected_account_id);
            v_cov_group_id := gen_random_uuid();

            SELECT id INTO v_cov_pos_id
              FROM public.positions
             WHERE lower(position_name) = lower(v_emp_rec.position)
             LIMIT 1;

            IF v_cov_pos_id IS NULL THEN
              SELECT position_id INTO v_cov_pos_id
                FROM public.v_account_position_options
               WHERE account_id = v_batch.selected_account_id
               LIMIT 1;
            END IF;

            INSERT INTO public.coverage_groups (
              id, coverage_code, account_id, position_id, employment_type,
              required_headcount, status, area_name, created_by, created_at
            ) VALUES (
              v_cov_group_id, v_cov_cgcode, v_batch.selected_account_id, v_cov_pos_id,
              COALESCE(v_emp_rec.civil_status, 'Regular'), 1, 'open',
              COALESCE(v_emp_rec.area_city, v_emp_rec.area_province),
              v_actor, now()
            );

            v_cov_anchor_id := COALESCE(v_primary_store_id, v_cov_store_ids[1]);
            IF NOT (v_cov_anchor_id = ANY(v_cov_store_ids)) THEN
              v_cov_anchor_id := v_cov_store_ids[1];
            END IF;

            FOREACH v_cov_s_id IN ARRAY v_cov_store_ids LOOP
              INSERT INTO public.coverage_group_stores (
                coverage_group_id, store_id, is_anchor, added_by, added_at, hc_share
              ) VALUES (
                v_cov_group_id, v_cov_s_id, (v_cov_s_id = v_cov_anchor_id),
                v_actor, now(), round(1.0 / array_length(v_cov_store_ids, 1), 4)
              ) ON CONFLICT (coverage_group_id, store_id) WHERE (archived_at IS NULL)
              DO UPDATE SET hc_share = round(1.0 / array_length(v_cov_store_ids, 1), 4);
            END LOOP;
          END IF;

          -- Provision slot in coverage_slots
          SELECT id INTO v_cov_slot_id
            FROM public.coverage_slots
           WHERE coverage_group_id = v_cov_group_id
             AND current_occupant_plantilla_id = v_plantilla_id
           LIMIT 1;

          IF v_cov_slot_id IS NULL THEN
            SELECT COALESCE(MAX(slot_ordinal), 0) + 1 INTO v_cov_slot_ord
              FROM public.coverage_slots
             WHERE coverage_group_id = v_cov_group_id;

            INSERT INTO public.coverage_slots (
              id, coverage_group_id, slot_ordinal, slot_status,
              current_occupant_plantilla_id, created_at, updated_at
            ) VALUES (
              gen_random_uuid(), v_cov_group_id, v_cov_slot_ord, 'active',
              v_plantilla_id, now(), now()
            ) RETURNING id INTO v_cov_slot_id;
          END IF;

          -- Bind to plantilla (clearing legacy roving_assignment_id per plantilla_roving_coverage_mutex_chk)
          UPDATE public.plantilla
             SET coverage_group_id = v_cov_group_id,
                 coverage_slot_id  = v_cov_slot_id,
                 roving_assignment_id = NULL,
                 deployment_type   = 'Roving',
                 updated_at        = now()
           WHERE id = v_plantilla_id;
        END IF;
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
          plantilla_id, employee_no, roving_group_id,
          store_id, vcode, store_name,
          account_id, group_id,
          filled_hc, active_store_count,
          schedule_days, schedule_time,
          effective_start, is_active,
          source_import_batch_id, created_by
        ) VALUES (
          v_plantilla_id, v_emp_rec.employee_no, v_cov_group_id,
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

REVOKE ALL ON FUNCTION public.approve_plantilla_import_batch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_batch(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.approve_plantilla_import_batch(uuid) IS
  'OHM2026_1053: Canonical merge of Migration 086 + ADR-002 Rule #17 Last-Row-Wins + ADR-002 Invariants 3 & 4 Universal Automatic Coverage Group Provisioning.';

COMMIT;
