-- ============================================================
-- Migration: 20262606000064_fix_plantilla_mother_account_configs_and_columns.sql
-- Purpose:
--   1. Create public.mother_account_configs table, RLS, policies & initial seed.
--   2. Add missing ADR-002 companion columns to plantilla_import_rows, stores,
--      accounts, plantilla, employee_store_allocations, plantilla_import_batches,
--      and employees.
--   3. Synchronize full ADR-002 parity for HRCO trigger, Zero-Edit lock helpers,
--      vcode validator, and batch review/approval/rollback lifecycle functions.
-- ============================================================

-- 1. Schema Additions / Adjustments

-- 1.1 Add mother_account and schedule fields to plantilla_import_rows
ALTER TABLE public.plantilla_import_rows
  ADD COLUMN IF NOT EXISTS mother_account text,
  ADD COLUMN IF NOT EXISTS schedule_days text,
  ADD COLUMN IF NOT EXISTS schedule_time text,
  ADD COLUMN IF NOT EXISTS needs_hrco boolean DEFAULT false;

-- 1.2 Add mother_account and schedule fields to stores
ALTER TABLE public.stores
  ADD COLUMN IF NOT EXISTS mother_account text,
  ADD COLUMN IF NOT EXISTS schedule_days text,
  ADD COLUMN IF NOT EXISTS schedule_time text;

-- 1.3 Add mother_account and schedule fields to accounts
ALTER TABLE public.accounts
  ADD COLUMN IF NOT EXISTS mother_account text,
  ADD COLUMN IF NOT EXISTS with_penalty boolean DEFAULT false;

-- 1.4 Add fields to plantilla
ALTER TABLE public.plantilla
  ADD COLUMN IF NOT EXISTS mother_account text,
  ADD COLUMN IF NOT EXISTS schedule_days text,
  ADD COLUMN IF NOT EXISTS schedule_time text,
  ADD COLUMN IF NOT EXISTS needs_hrco boolean DEFAULT false;

-- 1.5 Add fields to employee_store_allocations
ALTER TABLE public.employee_store_allocations
  ADD COLUMN IF NOT EXISTS schedule_days text,
  ADD COLUMN IF NOT EXISTS schedule_time text;

-- 1.6 Add tracking columns to plantilla_import_batches
ALTER TABLE public.plantilla_import_batches
  ADD COLUMN IF NOT EXISTS rollback_rejected_by uuid REFERENCES public.users_profile(id),
  ADD COLUMN IF NOT EXISTS rollback_rejected_at timestamptz,
  ADD COLUMN IF NOT EXISTS approved_by_name text,
  ADD COLUMN IF NOT EXISTS rejected_by_name text,
  ADD COLUMN IF NOT EXISTS error_message text;

-- 1.7 Add is_deleted to employees if not present
ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS is_deleted boolean DEFAULT false;

-- 1.8 Mother Account Configuration Table
CREATE TABLE IF NOT EXISTS public.mother_account_configs (
  mother_account text PRIMARY KEY,
  with_penalty boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS and add policies
ALTER TABLE public.mother_account_configs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "mother_account_configs_select_authenticated" ON public.mother_account_configs;
CREATE POLICY "mother_account_configs_select_authenticated"
  ON public.mother_account_configs
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "mother_account_configs_admin_all" ON public.mother_account_configs;
CREATE POLICY "mother_account_configs_admin_all"
  ON public.mother_account_configs
  FOR ALL
  TO authenticated
  USING (public.i_have_full_access())
  WITH CHECK (public.i_have_full_access());

GRANT SELECT, INSERT, UPDATE ON public.mother_account_configs TO authenticated;
GRANT ALL ON public.mother_account_configs TO service_role;

-- Seed mother_account_configs from existing stores and accounts
INSERT INTO public.mother_account_configs (mother_account, with_penalty)
SELECT DISTINCT upper(trim(a.account_name)), bool_or(COALESCE(s.with_penalty, false))
FROM public.accounts a
JOIN public.stores s ON s.account_id = a.id
WHERE a.account_name IS NOT NULL AND trim(a.account_name) <> ''
GROUP BY 1
ON CONFLICT (mother_account) DO NOTHING;

-- 2. Parsing Helpers
CREATE OR REPLACE FUNCTION public.safe_parse_date(p_str text)
 RETURNS date
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
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
$function$
;
GRANT EXECUTE ON FUNCTION public.safe_parse_date(text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.safe_parse_numeric(p_str text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
  IF p_str IS NULL OR trim(p_str) = '' THEN
    RETURN NULL;
  END IF;
  RETURN regexp_replace(p_str, '[^0-9.]', '', 'g')::numeric;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$function$
;
GRANT EXECUTE ON FUNCTION public.safe_parse_numeric(text) TO authenticated, service_role;

-- 3. Reactive Backfill: Account HRCO Assignment Trigger & Function
CREATE OR REPLACE FUNCTION public.fn_trg_account_hrco_backfill()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.hrco_user_id IS NOT NULL AND (OLD.hrco_user_id IS DISTINCT FROM NEW.hrco_user_id) THEN
    -- Backfill all plantilla rows for this account that need HRCO
    UPDATE public.plantilla
       SET hrco_user_id_snapshot = NEW.hrco_user_id,
           needs_hrco = false,
           updated_at = now()
     WHERE account_id = NEW.id
       AND needs_hrco = true;
  END IF;
  RETURN NEW;
END;
$function$
;
GRANT EXECUTE ON FUNCTION public.fn_trg_account_hrco_backfill() TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_account_hrco_backfill ON public.accounts;
CREATE TRIGGER trg_account_hrco_backfill
  AFTER UPDATE OF hrco_user_id ON public.accounts
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_account_hrco_backfill();

-- 4. Zero-Edit Lock Helper Functions with False-Positive Guard
DROP FUNCTION IF EXISTS public._import_records_modified_after_approval(uuid, timestamptz);
DROP FUNCTION IF EXISTS public._import_records_modified_after_approval(uuid, timestamp with time zone);
CREATE OR REPLACE FUNCTION public._import_records_modified_after_approval(p_module text, p_batch_id uuid, p_approved_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_batch_status text;
  v_grace_approved_at timestamptz;
BEGIN
  IF p_approved_at IS NULL THEN
    RETURN false;
  END IF;

  v_grace_approved_at := p_approved_at + interval '2 seconds';

  IF p_module = 'plantilla' THEN
    SELECT b.status INTO v_batch_status
      FROM public.plantilla_import_batches b
     WHERE b.id = p_batch_id;

    IF v_batch_status = 'rolled_back' THEN
      RETURN false;
    END IF;

    RETURN EXISTS (
      SELECT 1
        FROM public.plantilla_import_commit_snapshots s
        JOIN public.plantilla p ON p.id = s.entity_id
       WHERE s.batch_id = p_batch_id
         AND s.entity_type = 'plantilla'
         AND s.action IN ('insert', 'update', 'reactivate')
         AND (
           p.source_baseline_import_batch_id IS DISTINCT FROM p_batch_id
           OR p.updated_at > v_grace_approved_at
         )
    ) OR EXISTS (
      SELECT 1
        FROM public.plantilla_import_commit_snapshots s
        JOIN public.stores st ON st.id = s.entity_id
       WHERE s.batch_id = p_batch_id
         AND s.entity_type = 'store'
         AND s.action IN ('insert', 'update')
         AND (
           st.source_import_id IS DISTINCT FROM p_batch_id
           OR st.updated_at > v_grace_approved_at
         )
    ) OR EXISTS (
      SELECT 1
        FROM public.employee_store_allocations a
       WHERE a.source_import_batch_id = p_batch_id
         AND a.created_at > v_grace_approved_at
    );
  END IF;

  IF p_module = 'vacancy' THEN
    RETURN EXISTS (
      SELECT 1 FROM public.vacancies v
       WHERE v.source_vacancy_import_batch_id = p_batch_id
         AND v.updated_at > v_grace_approved_at
    );
  END IF;

  RETURN false;
END;
$function$
;
GRANT EXECUTE ON FUNCTION public._import_records_modified_after_approval(text, uuid, timestamp with time zone) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_plantilla_import_first_modified_record(p_batch_id uuid, p_approved_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec record;
  v_grace_approved_at timestamptz := p_approved_at + interval '2 seconds';
BEGIN
  IF p_approved_at IS NULL THEN
    RETURN NULL;
  END IF;

  -- Check plantilla rows
  SELECT p.employee_no, p.employee_name, p.updated_at, 'plantilla' AS entity
    INTO v_rec
    FROM public.plantilla_import_commit_snapshots s
    JOIN public.plantilla p ON p.id = s.entity_id
   WHERE s.batch_id = p_batch_id
     AND s.entity_type = 'plantilla'
     AND s.action IN ('insert', 'update', 'reactivate')
     AND (
       p.source_baseline_import_batch_id IS DISTINCT FROM p_batch_id
       OR p.updated_at > v_grace_approved_at
     )
   ORDER BY p.updated_at DESC
   LIMIT 1;

  IF v_rec.employee_no IS NOT NULL THEN
    RETURN jsonb_build_object(
      'entity', v_rec.entity,
      'employee_no', v_rec.employee_no,
      'employee_name', v_rec.employee_name,
      'updated_at', v_rec.updated_at
    );
  END IF;

  -- Check stores
  SELECT st.vcode, st.store_name, st.updated_at, 'store' AS entity
    INTO v_rec
    FROM public.plantilla_import_commit_snapshots s
    JOIN public.stores st ON st.id = s.entity_id
   WHERE s.batch_id = p_batch_id
     AND s.entity_type = 'store'
     AND s.action IN ('insert', 'update')
     AND (
       st.source_import_id IS DISTINCT FROM p_batch_id
       OR st.updated_at > v_grace_approved_at
     )
   ORDER BY st.updated_at DESC
   LIMIT 1;

  IF v_rec.vcode IS NOT NULL THEN
    RETURN jsonb_build_object(
      'entity', v_rec.entity,
      'vcode', v_rec.vcode,
      'store_name', v_rec.store_name,
      'updated_at', v_rec.updated_at
    );
  END IF;

  RETURN NULL;
END;
$function$
;
GRANT EXECUTE ON FUNCTION public.get_plantilla_import_first_modified_record(uuid, timestamp with time zone) TO authenticated, service_role;

-- 5. Downstream Invariant 1 Assertion Helper
CREATE OR REPLACE FUNCTION public.fn_assert_vcode_exists_in_plantilla(p_vcode text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.stores s WHERE upper(s.vcode) = upper(trim(p_vcode))
  ) OR EXISTS (
    SELECT 1 FROM public.plantilla_slots ps WHERE upper(ps.legacy_vcode) = upper(trim(p_vcode))
  );
$function$
;
GRANT EXECUTE ON FUNCTION public.fn_assert_vcode_exists_in_plantilla(text) TO authenticated, service_role;

-- 6. Batch Approval, Rejection & Rollback Lifecycle Functions
CREATE OR REPLACE FUNCTION public.approve_plantilla_import_batch(p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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
$function$
;
REVOKE ALL ON FUNCTION public.approve_plantilla_import_batch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_batch(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reject_plantilla_import_batch(p_batch_id uuid, p_reason_code text, p_reason_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid     uuid := auth.uid();
  v_batch   public.plantilla_import_batches%ROWTYPE;
  v_code    text := COALESCE(lower(trim(p_reason_code)), '');
  v_note    text := NULLIF(trim(COALESCE(p_reason_note,'')), '');
  v_label   text;
  v_display text;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  IF v_code = '' THEN
    RAISE EXCEPTION 'INVALID_INPUT: rejection reason is required'
      USING ERRCODE = '22023';
  END IF;

  v_label := CASE v_code
    WHEN 'wrong_group_account'       THEN 'Wrong Group/Account selected'
    WHEN 'invalid_csv'               THEN 'Invalid CSV / wrong template'
    WHEN 'duplicate_vcode'           THEN 'Duplicate VCODE issue'
    WHEN 'invalid_vacancy_data'      THEN 'Invalid vacancy data'
    WHEN 'applicant_data_incomplete' THEN 'Applicant data incomplete'
    WHEN 'uploaded_by_mistake'       THEN 'Uploaded by mistake'
    WHEN 'other'                     THEN 'Other'
    ELSE NULL
  END;
  IF v_label IS NULL THEN
    RAISE EXCEPTION 'INVALID_INPUT: unsupported rejection reason "%"', p_reason_code
      USING ERRCODE = '22023';
  END IF;

  IF v_code = 'other' AND v_note IS NULL THEN
    RAISE EXCEPTION 'INVALID_INPUT: remarks are required when reason is "Other"'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;

  IF v_batch.status NOT IN ('pending_approval', 'pending_review', 'validation_failed', 'draft_uploaded', 'commit_failed', 'blocked', 'partially_blocked') THEN
    RAISE EXCEPTION 'INVALID_STATE: cannot reject batch in % state', v_batch.status
      USING ERRCODE = '22023';
  END IF;

  v_display := CASE WHEN v_note IS NULL THEN v_label
                    ELSE v_label || ' — ' || v_note END;

  UPDATE public.plantilla_import_batches
     SET status                = 'rejected',
         rejected_by           = v_uid,
         rejected_at           = now(),
         rejection_reason_code = v_code,
         rejection_reason_note = v_note,
         rejection_reason      = v_display,
         updated_at            = now()
   WHERE id = p_batch_id;

  -- Audit uses UPDATE (no new audit_action enum labels — OHM2026_1146).
  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'plantilla_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object(
      'event',       'rejected',
      'reason_code', v_code,
      'reason_note', v_note,
      'new_status',  'rejected'
    ));

  RETURN jsonb_build_object(
    'batch_id',              p_batch_id,
    'status',                'rejected',
    'rejection_reason_code', v_code,
    'rejection_reason_note', v_note
  );
END$function$
;
REVOKE ALL ON FUNCTION public.reject_plantilla_import_batch(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_plantilla_import_batch(uuid, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.request_plantilla_import_rollback(p_batch_id uuid, p_reason_code text, p_reason_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid         uuid := auth.uid();
  v_batch       public.plantilla_import_batches%ROWTYPE;
  v_modified    jsonb;
BEGIN
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'INVALID_STATE: only approved batches can be requested for rollback (current=%)', v_batch.status USING ERRCODE = '22023';
  END IF;

  -- 72-hour window check
  IF now() > (v_batch.approved_at + interval '72 hours') THEN
    RAISE EXCEPTION 'ROLLBACK_WINDOW_EXPIRED: 72-hour rollback request window has expired' USING ERRCODE = '22023';
  END IF;

  -- Strict Zero-Edit Lock Check
  v_modified := public.get_plantilla_import_first_modified_record(p_batch_id, v_batch.approved_at);
  IF v_modified IS NOT NULL THEN
    RAISE EXCEPTION 'ZERO_EDIT_LOCK: Batch records have been modified post-approval. Employee % (%) was edited on %. Rollback is hard-blocked.',
      v_modified->>'employee_no', v_modified->>'employee_name', v_modified->>'updated_at'
      USING ERRCODE = '40001';
  END IF;

  UPDATE public.plantilla_import_batches
     SET rollback_status       = 'requested',
         rollback_requested_by = v_uid,
         rollback_requested_at = now(),
         rollback_reason       = p_reason_note,
         rollback_reason_code  = p_reason_code,
         rollback_reason_note  = p_reason_note,
         updated_at            = now()
   WHERE id = p_batch_id;

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'rollback_status', 'requested'
  );
END$function$
;
REVOKE ALL ON FUNCTION public.request_plantilla_import_rollback(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_plantilla_import_rollback(uuid, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.approve_plantilla_import_rollback(p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid       uuid := auth.uid();
  v_actor     uuid := public.get_current_profile_id();
  v_user_name text;
  v_batch     public.plantilla_import_batches%ROWTYPE;
  v_modified  jsonb;
  v_res       jsonb;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT full_name INTO v_user_name FROM public.users_profile WHERE id = v_actor;

  -- Strict Zero-Edit Lock Check
  v_modified := public.get_plantilla_import_first_modified_record(p_batch_id, v_batch.approved_at);
  IF v_modified IS NOT NULL THEN
    RAISE EXCEPTION 'ZERO_EDIT_LOCK: Batch records have been modified post-approval. Employee % (%) was edited on %. Rollback is hard-blocked.',
      v_modified->>'employee_no', v_modified->>'employee_name', v_modified->>'updated_at'
      USING ERRCODE = '40001';
  END IF;

  -- Execute rollback
  v_res := public.rollback_plantilla_import_batch(p_batch_id, COALESCE(v_batch.rollback_reason_note, 'Approved by admin'));

  UPDATE public.plantilla_import_batches
     SET rollback_status      = 'completed',
         rollback_approved_by = v_uid,
         rollback_approved_at = now(),
         approved_by_name     = v_user_name,
         updated_at           = now()
   WHERE id = p_batch_id;

  RETURN v_res;
END$function$
;
REVOKE ALL ON FUNCTION public.approve_plantilla_import_rollback(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_rollback(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reject_plantilla_import_rollback(p_batch_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid       uuid := auth.uid();
  v_actor     uuid := public.get_current_profile_id();
  v_user_name text;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required' USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: rejection reason required' USING ERRCODE = '22023';
  END IF;

  SELECT full_name INTO v_user_name FROM public.users_profile WHERE id = v_actor;

  UPDATE public.plantilla_import_batches
     SET rollback_status        = 'rejected',
         rollback_rejected_by   = v_actor,
         rollback_rejected_at   = now(),
         rejected_by_name       = v_user_name,
         rollback_error_detail  = p_reason,
         updated_at             = now()
   WHERE id = p_batch_id;

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'rollback_status', 'rejected'
  );
END$function$
;
REVOKE ALL ON FUNCTION public.reject_plantilla_import_rollback(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_plantilla_import_rollback(uuid, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.override_plantilla_import_rollback(p_batch_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN public.emergency_rollback_plantilla_import(p_batch_id, p_reason);
END$function$
;
REVOKE ALL ON FUNCTION public.override_plantilla_import_rollback(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.override_plantilla_import_rollback(uuid, text) TO authenticated, service_role;
