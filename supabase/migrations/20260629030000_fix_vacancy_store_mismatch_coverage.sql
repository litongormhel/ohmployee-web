-- Migration: 20260629030000_fix_vacancy_store_mismatch_coverage
-- Created: 2026-06-29
-- Ticket: ohm#9x4p2k7q
-- Purpose: Fix newly created vacant stores missing from Coverage Request -> Add Store picker.
--
-- Root Cause:
--   1. fn_trg_auto_create_vacancy_slot() resolved the plantilla slot's store_id by looking up
--      stores.vcode = NEW.vcode. For newly created vacant stores, the store does not have its
--      vcode set/synced yet, resulting in plantilla_slots.store_id being NULL.
--   2. Stores with null plantilla_slots.store_id and no employee store allocations are skipped
--      in get_coverage_group_eligible_stores() filter.
--   3. create_plantilla_slot_from_request() generated new VCodes without syncing them back
--      to public.stores.vcode.
--
-- Fix:
--   1. Update fn_trg_auto_create_vacancy_slot() to prioritize NEW.store_id. Only fall back
--      to stores.vcode lookup when NEW.store_id IS NULL.
--   2. Update create_plantilla_slot_from_request() to sync newly generated VCodes to
--      public.stores.vcode for the target store, without overwriting existing different VCodes.
--   3. Merge the stationary VCode reuse logic (from 20261216000000) and the roving store-array
--      path (from 20261238000000) so all optimizations are preserved.
--   4. Run a safe backfill script to repair existing null store_id values in plantilla_slots
--      and missing stores.vcode values.
-- ============================================================

BEGIN;

-- ============================================================
-- §1  Update Trigger Function: fn_trg_auto_create_vacancy_slot
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_trg_auto_create_vacancy_slot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_required_hc  int;
  v_max_ordinal  int;
  v_slot_id      uuid;
  v_store_id     uuid;
  v_ordinal      int;
  v_slot_status  text;
  v_aging_ts     timestamptz;
  v_emp_type     text;
BEGIN
  -- Only fire for non-pool, non-deleted, non-roving, VCODE-bearing vacancies
  -- that have affects_required_hc = true (or NULL, which defaults to true).
  IF COALESCE(NEW.is_pool_vacancy, false)       = true  THEN RETURN NEW; END IF;
  IF NEW.deleted_at IS NOT NULL                          THEN RETURN NEW; END IF;
  IF NEW.vcode IS NULL                                   THEN RETURN NEW; END IF;
  IF COALESCE(NEW.affects_required_hc, true)    = false THEN RETURN NEW; END IF;

  -- Only fire when the vacancy is entering or staying at Open/Pipeline
  IF lower(NEW.status) NOT IN ('open', 'pipeline') THEN RETURN NEW; END IF;

  -- On UPDATE: skip if status did not change to/from an open state
  -- (avoids re-firing on unrelated column updates when status is already Open)
  IF TG_OP = 'UPDATE' THEN
    IF lower(OLD.status) = lower(NEW.status) THEN
      -- Status unchanged — only re-evaluate if required_headcount increased
      IF COALESCE(NEW.required_headcount, 1) <= COALESCE(OLD.required_headcount, 1) THEN
        RETURN NEW;
      END IF;
    END IF;
  END IF;

  v_required_hc := GREATEST(COALESCE(NEW.required_headcount, 1), 1);
  v_slot_status  := CASE
                      WHEN lower(NEW.status) = 'pipeline' THEN 'pipeline'
                      ELSE 'open'
                    END;
  v_aging_ts     := COALESCE(NEW.vacant_date::timestamptz, now());
  v_emp_type     := COALESCE(NEW.employment_type, 'stationary');

  -- Resolve store_id, prioritizing NEW.store_id
  IF NEW.store_id IS NOT NULL THEN
    v_store_id := NEW.store_id;
  ELSE
    SELECT s.id INTO v_store_id
    FROM public.stores s
    WHERE upper(s.vcode) = upper(NEW.vcode)
      AND s.status = 'active'
    ORDER BY s.created_at
    LIMIT 1;
  END IF;

  -- Determine how many slots already exist for this VCODE
  SELECT COALESCE(MAX(ps.slot_ordinal), 0) INTO v_max_ordinal
  FROM public.plantilla_slots ps
  WHERE ps.legacy_vcode = NEW.vcode;

  -- Create only the missing ordinals (v_max_ordinal+1 .. required_hc)
  FOR v_ordinal IN (v_max_ordinal + 1) .. v_required_hc LOOP
    -- Idempotency guard
    IF EXISTS (
      SELECT 1 FROM public.plantilla_slots ps2
      WHERE ps2.legacy_vcode = NEW.vcode
        AND ps2.slot_ordinal = v_ordinal
    ) THEN
      CONTINUE;
    END IF;

    INSERT INTO public.plantilla_slots (
      store_id,
      account_id,
      group_id,
      position,
      employment_type,
      is_roving,
      slot_status,
      slot_ordinal,
      legacy_vcode,
      source_hc_request_id,
      created_at,
      updated_at
    ) VALUES (
      v_store_id,
      NEW.account_id,
      NEW.group_id,
      COALESCE(NEW.position, ''),
      v_emp_type,
      false,
      v_slot_status,
      v_ordinal::smallint,
      NEW.vcode,
      NULL,
      now(),
      now()
    )
    RETURNING id INTO v_slot_id;

    INSERT INTO public.slot_history (
      slot_id,
      account_id,
      action_type,
      old_value,
      new_value,
      reason_code,
      performed_by,
      remarks,
      created_at
    ) VALUES (
      v_slot_id,
      NEW.account_id,
      'status_change',
      NULL,
      v_slot_status,
      NULL,
      public.get_current_profile_id(),
      'Auto-created by fn_trg_auto_create_vacancy_slot on vacancy ' || NEW.vcode,
      v_aging_ts
    );
  END LOOP;

  RETURN NEW;
END$func$;

COMMENT ON FUNCTION public.fn_trg_auto_create_vacancy_slot() IS
  'OHM2026_0074 / ohm#9x4p2k7q — Auto-creates plantilla_slots for newly opened/pipeline vacancies. '
  'Prioritizes NEW.store_id and falls back to stores.vcode lookup only when NEW.store_id IS NULL.';


-- ============================================================
-- §2  Update Request Completion: create_plantilla_slot_from_request
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_plantilla_slot_from_request(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role               text := public.get_my_role();
  v_req                public.headcount_requests%ROWTYPE;
  v_account            public.accounts%ROWTYPE;
  v_store              public.stores%ROWTYPE;
  v_position           public.positions%ROWTYPE;
  v_coverage_group     public.coverage_groups%ROWTYPE;
  v_store_name         text;
  v_store_id           uuid;
  v_vcode              text;
  v_vcodes             text[];
  v_plantilla_id       uuid;
  v_vacancy_id         uuid;
  v_first_plantilla_id uuid;
  v_count              integer;
  i                    integer;
  v_triggered_by_id    uuid;
  v_triggered_by_name  text;
  v_hrco_user_id       uuid;
  v_hrco_name          text;
  v_group_id           uuid;
  v_group_name         text;
  v_slot_result        jsonb;
  v_max_ordinal        integer;
  -- store-array path
  v_hc_store_row       public.hc_request_stores%ROWTYPE;
  v_new_cg_id          uuid;
  v_cg_code            text;
  v_store_vcodes       jsonb := '[]'::jsonb;
  v_stores_added       integer := 0;
  v_store_row          public.stores%ROWTYPE;
  -- stationary path VCODE reuse fields
  v_reused_vcode       boolean := false;
BEGIN
  IF NOT (v_role IN ('Encoder', 'Super Admin', 'Head Admin')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  PERFORM public.fn_assert_freeze_inactive('recruitment_freeze');

  SELECT * INTO v_req
  FROM public.headcount_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  IF v_req.status <> 'approved_pending_vcode' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_approved', 'current', v_req.status);
  END IF;

  v_count := COALESCE(v_req.headcount_needed, 1);

  IF v_count < 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_headcount_needed');
  END IF;

  IF v_count > 20 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'headcount_limit_exceeded', 'max', 20);
  END IF;

  SELECT * INTO v_account FROM public.accounts WHERE id = v_req.account_id;
  IF v_account.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'account_id');
  END IF;

  SELECT * INTO v_position FROM public.positions WHERE id = v_req.position_id;
  IF v_position.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'position_id');
  END IF;

  v_triggered_by_id := public.get_current_profile_id();
  SELECT full_name INTO v_triggered_by_name
  FROM public.users_profile WHERE id = v_triggered_by_id;

  v_group_id := COALESCE(v_req.group_id, v_account.group_id);
  SELECT group_name INTO v_group_name FROM public.groups WHERE id = v_group_id;

  v_hrco_user_id := v_account.hrco_user_id;
  IF v_hrco_user_id IS NOT NULL THEN
    SELECT full_name INTO v_hrco_name
    FROM public.users_profile WHERE id = v_hrco_user_id;
  END IF;

  -- ── Detect roving path ─────────────────────────────────────────────────────
  IF lower(coalesce(v_req.workforce_type, 'stationary')) = 'roving' THEN

    -- Check if this is the new store-array path
    IF EXISTS (
      SELECT 1 FROM public.hc_request_stores WHERE request_id = p_request_id LIMIT 1
    ) THEN
      -- ══ NEW ROVING STORE-ARRAY PATH ══════════════════════════════════════
      -- Creates N VCodes (one per store) + 1 CGCode
      -- ═════════════════════════════════════════════════════════════════════
      v_vcodes := ARRAY[]::text[];

      -- Step 1: Create the Coverage Group (structure only)
      v_new_cg_id := gen_random_uuid();
      v_cg_code   := public.fn_generate_cgcode_for_account(v_req.account_id);

      INSERT INTO public.coverage_groups (
        id, account_id, group_id, position_id,
        coverage_code, area_name, employment_type,
        status, required_headcount,
        created_by, updated_by
      ) VALUES (
        v_new_cg_id,
        v_req.account_id,
        v_group_id,
        v_req.position_id,
        v_cg_code,
        COALESCE(v_req.area, ''),
        COALESCE(v_req.employment_type, 'Roving'),
        'open',
        v_count,
        v_triggered_by_id,
        v_triggered_by_id
      );

      -- Step 2: For each store in hc_request_stores, create VCode + Vacancy + Slot
      FOR v_hc_store_row IN
        SELECT * FROM public.hc_request_stores
        WHERE request_id = p_request_id
        ORDER BY sort_order ASC
      LOOP
        SELECT * INTO v_store_row FROM public.stores WHERE id = v_hc_store_row.store_id;

        -- Reuse existing VCODE for store if active vacancy exists
        v_vcode := public.find_reusable_store_vcode(v_req.account_id, v_hc_store_row.store_id, v_hc_store_row.store_name_snapshot);

        IF v_vcode IS NULL THEN
          v_vcode := public.generate_vcode_for_account(v_req.account_id);

          -- Sync this new VCode to public.stores.vcode
          IF v_hc_store_row.store_id IS NOT NULL THEN
            UPDATE public.stores
            SET vcode = v_vcode
            WHERE id = v_hc_store_row.store_id
              AND (vcode IS NULL OR trim(vcode) = '');
          END IF;
        END IF;

        v_vcodes := array_append(v_vcodes, v_vcode);

        -- Upsert vacancy for this store
        INSERT INTO public.vacancies (
          vcode, account, position, status,
          account_id, store_id, position_id, group_id,
          area_name, store_name, vacant_date,
          required_headcount, source_plantilla_id,
          vacancy_type, employment_type, urgency_level,
          target_fill_date, triggered_by_user_id, triggered_by_name,
          hrco_user_id, hrco_name,
          source, source_headcount_request_id,
          area_city, province, store_branch,
          chain, chain_id,
          created_by, updated_by
        ) VALUES (
          v_vcode,
          v_account.account_name,
          v_position.position_name,
          'Open',
          v_account.id,
          v_hc_store_row.store_id,
          v_position.id,
          v_group_id,
          COALESCE(v_hc_store_row.province_snapshot, v_store_row.province, v_store_row.area_province),
          v_hc_store_row.store_name_snapshot,
          COALESCE(v_req.vacant_date, CURRENT_DATE),
          1,  -- 1 HC per store; total coverage HC = v_count slots on the CG
          NULL,
          CASE WHEN v_req.request_type = 'Replacement' THEN 'Replacement' ELSE 'New' END,
          COALESCE(v_req.employment_type, 'Roving'),
          v_req.urgency,
          v_req.target_fill_date,
          v_triggered_by_id, v_triggered_by_name,
          v_hrco_user_id, v_hrco_name,
          'hc_request', p_request_id,
          v_hc_store_row.city_snapshot,
          v_hc_store_row.province_snapshot,
          v_store_row.store_branch,
          v_group_name, v_group_id,
          v_triggered_by_id, v_triggered_by_id
        )
        ON CONFLICT (vcode) DO UPDATE
          SET required_headcount = public.vacancies.required_headcount + 1,
              updated_by = v_triggered_by_id
        RETURNING id INTO v_vacancy_id;

        -- Create or adopt plantilla_slots for this store VCode
        IF NOT EXISTS (
          SELECT 1 FROM public.plantilla_slots WHERE legacy_vcode = v_vcode LIMIT 1
        ) THEN
          PERFORM public.fn_create_slots_from_hc_request(p_request_id, 1, v_vcode);
        END IF;

        -- Add store to coverage_group_stores
        INSERT INTO public.coverage_group_stores (
          coverage_group_id, store_id, store_name_snapshot, account_id
        ) VALUES (
          v_new_cg_id,
          v_hc_store_row.store_id,
          v_hc_store_row.store_name_snapshot,
          v_req.account_id
        )
        ON CONFLICT DO NOTHING;

        v_stores_added := v_stores_added + 1;
      END LOOP;

      -- Step 3: Create coverage slots for the overall CG demand
      SELECT COALESCE(MAX(slot_ordinal), 0)
        INTO v_max_ordinal
      FROM public.coverage_slots
      WHERE coverage_group_id = v_new_cg_id;

      INSERT INTO public.coverage_slots (coverage_group_id, slot_ordinal, slot_status)
      SELECT v_new_cg_id, v_max_ordinal + gs.ord, 'open'
      FROM generate_series(1, v_count) AS gs(ord);

      -- Step 4: Finalise the HC request
      UPDATE public.headcount_requests
      SET status                      = 'completed',
          vacancy_created             = true,
          slot_created_by_user_id     = v_triggered_by_id,
          slot_created_at             = NOW(),
          coverage_group_id           = v_new_cg_id,
          coverage_group_code_snapshot = v_cg_code,
          created_vcode               = NULL,
          created_vcodes              = v_vcodes
      WHERE id = p_request_id;

      RETURN jsonb_build_object(
        'ok',                    true,
        'request_id',            p_request_id,
        'workforce_type',        'roving',
        'path',                  'store_array',
        'coverage_group_id',     v_new_cg_id,
        'coverage_code',         v_cg_code,
        'stores_processed',      v_stores_added,
        'vcodes',                v_vcodes,
        'vcode_count',           array_length(v_vcodes, 1),
        'coverage_slots_created', v_count,
        'vacancy_created',       true
      );

    ELSE
      -- ══ OLD ROVING PATH: add coverage slots to existing CG (UNCHANGED) ══
      IF v_req.coverage_group_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'coverage_group_required_for_roving');
      END IF;

      SELECT * INTO v_coverage_group
      FROM public.coverage_groups
      WHERE id = v_req.coverage_group_id
        AND account_id = v_req.account_id
        AND archived_at IS NULL
      FOR UPDATE;

      IF v_coverage_group.id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'coverage_group_id');
      END IF;

      IF v_coverage_group.position_id <> v_req.position_id THEN
        RETURN jsonb_build_object('ok', false, 'error', 'coverage_group_position_mismatch');
      END IF;

      SELECT COALESCE(MAX(slot_ordinal), 0)
        INTO v_max_ordinal
      FROM public.coverage_slots
      WHERE coverage_group_id = v_coverage_group.id;

      INSERT INTO public.coverage_slots (coverage_group_id, slot_ordinal, slot_status)
      SELECT v_coverage_group.id, v_max_ordinal + gs.ord, 'open'
      FROM generate_series(1, v_count) AS gs(ord);

      UPDATE public.coverage_groups
      SET required_headcount = required_headcount + v_count,
          status = 'open'
      WHERE id = v_coverage_group.id;

      UPDATE public.headcount_requests
      SET status                      = 'completed',
          vacancy_created             = true,
          slot_created_by_user_id     = v_triggered_by_id,
          slot_created_at             = NOW(),
          coverage_group_code_snapshot = COALESCE(coverage_group_code_snapshot, v_coverage_group.coverage_code),
          created_vcode               = NULL,
          created_vcodes              = ARRAY[]::text[]
      WHERE id = p_request_id;

      RETURN jsonb_build_object(
        'ok',                    true,
        'request_id',            p_request_id,
        'headcount_created',     v_count,
        'workforce_type',        'roving',
        'path',                  'coverage_group',
        'coverage_group_id',     v_coverage_group.id,
        'coverage_code',         v_coverage_group.coverage_code,
        'coverage_slots_created', v_count,
        'vacancy_created',       true
      );
    END IF;
  END IF;

  -- ── Floating path ──────────────────────────────────────────────────────────
  IF lower(coalesce(v_req.workforce_type, 'stationary')) = 'floating' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'floating_workforce_not_enabled');
  END IF;

  -- ── Stationary path ────────────────────────────────────────────────────────
  IF v_req.store_id IS NOT NULL THEN
    SELECT * INTO v_store FROM public.stores WHERE id = v_req.store_id;
  END IF;

  v_store_name := NULLIF(TRIM(COALESCE(v_store.store_name, v_req.store_name_snapshot)), '');
  v_store_id   := v_store.id;

  IF v_store_name IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'store_name');
  END IF;

  -- ── ohm#9kq4m2z8: 1-store-1-VCODE reuse check ─────────────────────────────
  v_vcode := public.find_reusable_store_vcode(v_account.id, v_store_id, v_store_name);

  IF v_vcode IS NOT NULL THEN
    v_reused_vcode := true;

    SELECT id INTO v_vacancy_id
    FROM public.vacancies
    WHERE vcode                          = v_vcode
      AND status                         IN ('Open', 'Pipeline')
      AND COALESCE(is_archived, false)   = false
      AND deleted_at                     IS NULL
    LIMIT 1;

    IF v_vacancy_id IS NULL THEN
      v_vcode        := public.generate_vcode_for_account(v_account.id);
      v_reused_vcode := false;

      INSERT INTO public.vacancies (
        vcode, account, position, status,
        account_id, store_id, position_id, group_id,
        area_name, store_name, vacant_date,
        required_headcount, source_plantilla_id,
        vacancy_type, employment_type, urgency_level,
        target_fill_date, triggered_by_user_id, triggered_by_name,
        hrco_user_id, hrco_name,
        source, source_headcount_request_id,
        area_city, province, store_branch,
        chain, chain_id,
        created_by, updated_by
      ) VALUES (
        v_vcode, v_account.account_name, v_position.position_name, 'Open',
        v_account.id, v_store_id, v_position.id, v_group_id,
        COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
        v_store_name,
        COALESCE(v_req.vacant_date, CURRENT_DATE),
        v_count,
        NULL,
        CASE WHEN v_req.request_type = 'Replacement' THEN 'Replacement' ELSE 'New' END,
        v_req.employment_type, v_req.urgency, v_req.target_fill_date,
        v_triggered_by_id, v_triggered_by_name,
        v_hrco_user_id, v_hrco_name,
        'hc_request', p_request_id,
        COALESCE(v_store.area_city, v_req.city_municipality),
        COALESCE(v_store.province, NULLIF(TRIM(v_req.area), '')),
        v_store.store_branch,
        v_group_name, v_group_id,
        v_triggered_by_id, v_triggered_by_id
      ) RETURNING id INTO v_vacancy_id;

      -- Sync this new VCode to public.stores.vcode
      IF v_store_id IS NOT NULL THEN
        UPDATE public.stores
        SET vcode = v_vcode
        WHERE id = v_store_id
          AND (vcode IS NULL OR trim(vcode) = '');
      END IF;
    ELSE
      UPDATE public.vacancies
      SET required_headcount = required_headcount + v_count,
          updated_by         = v_triggered_by_id,
          updated_at         = NOW()
      WHERE id = v_vacancy_id;
    END IF;

  ELSE
    v_vcode := public.generate_vcode_for_account(v_account.id);

    INSERT INTO public.vacancies (
      vcode, account, position, status,
      account_id, store_id, position_id, group_id,
      area_name, store_name, vacant_date,
      required_headcount, source_plantilla_id,
      vacancy_type, employment_type, urgency_level,
      target_fill_date, triggered_by_user_id, triggered_by_name,
      hrco_user_id, hrco_name,
      source, source_headcount_request_id,
      area_city, province, store_branch,
      chain, chain_id,
      created_by, updated_by
    ) VALUES (
      v_vcode, v_account.account_name, v_position.position_name, 'Open',
      v_account.id, v_store_id, v_position.id, v_group_id,
      COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
      v_store_name,
      COALESCE(v_req.vacant_date, CURRENT_DATE),
      v_count,
      NULL,
      CASE WHEN v_req.request_type = 'Replacement' THEN 'Replacement' ELSE 'New' END,
      v_req.employment_type, v_req.urgency, v_req.target_fill_date,
      v_triggered_by_id, v_triggered_by_name,
      v_hrco_user_id, v_hrco_name,
      'hc_request', p_request_id,
      COALESCE(v_store.area_city, v_req.city_municipality),
      COALESCE(v_store.province, NULLIF(TRIM(v_req.area), '')),
      v_store.store_branch,
      v_group_name, v_group_id,
      v_triggered_by_id, v_triggered_by_id
    ) RETURNING id INTO v_vacancy_id;

    -- Sync this new VCode to public.stores.vcode
    IF v_store_id IS NOT NULL THEN
      UPDATE public.stores
      SET vcode = v_vcode
      WHERE id = v_store_id
        AND (vcode IS NULL OR trim(vcode) = '');
    END IF;
  END IF;

  v_vcodes := ARRAY[v_vcode];

  -- ── Plantilla (VACANT SLOT) rows ──
  FOR i IN 1..v_count LOOP
    INSERT INTO public.plantilla (
      employee_name, employee_no,
      account, status, vcode, position,
      account_id, store_id, area, position_id,
      store_name, deployment_type,
      source_headcount_request_id,
      chain_id,
      created_by, updated_by, tagged_at
    ) VALUES (
      '(VACANT SLOT)', '(PENDING)',
      v_account.account_name, 'Inactive', v_vcode, v_position.position_name,
      v_account.id, v_store_id,
      COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
      v_position.id,
      v_store_name, v_req.employment_type,
      p_request_id,
      v_group_id,
      v_triggered_by_id, v_triggered_by_id, CURRENT_DATE
    ) RETURNING id INTO v_plantilla_id;

    IF v_first_plantilla_id IS NULL THEN
      v_first_plantilla_id := v_plantilla_id;
    END IF;
  END LOOP;

  -- Link vacancy back to first plantilla if this was a new vacancy
  IF NOT v_reused_vcode THEN
    UPDATE public.vacancies
    SET source_plantilla_id = v_first_plantilla_id,
        updated_by          = v_triggered_by_id
    WHERE id = v_vacancy_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.plantilla_slots
    WHERE legacy_vcode = v_vcode
    LIMIT 1
  ) THEN
    UPDATE public.plantilla_slots
    SET source_hc_request_id = p_request_id,
        updated_by           = v_triggered_by_id,
        updated_at           = now()
    WHERE legacy_vcode = v_vcode
      AND source_hc_request_id IS NULL;

    v_slot_result := jsonb_build_object(
      'ok',      true,
      'adopted', true,
      'hint',    'slots created by trg_auto_create_vacancy_slot; linked to HC request'
    );
  ELSE
    v_slot_result := public.fn_create_slots_from_hc_request(p_request_id, v_count, v_vcode);
  END IF;

  UPDATE public.headcount_requests
  SET status                  = 'completed',
      vacancy_created         = true,
      slot_created_by_user_id = v_triggered_by_id,
      slot_created_at         = NOW(),
      created_plantilla_id    = v_first_plantilla_id,
      created_vcode           = v_vcode,
      created_vcodes          = v_vcodes
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'ok',                true,
    'request_id',        p_request_id,
    'headcount_created', v_count,
    'workforce_type',    'stationary',
    'vcode_count',       1,
    'vcodes',            v_vcodes,
    'vacancy_created',   true,
    'reused_vcode',      v_reused_vcode,
    'slot_result',       v_slot_result
  );
END;
$function$;

COMMENT ON FUNCTION public.create_plantilla_slot_from_request(uuid) IS
  'Completes an approved HC request by creating a vacancy + plantilla (VACANT SLOT) rows. '
  'Stationary path: enforces 1-store-1-VCODE by reusing the existing active vacancy VCODE '
  'when the store already has one (ohm#9kq4m2z8). Roving path: adds coverage_slots and '
  'increments the coverage group headcount. Returns reused_vcode=true when reuse occurred. '
  'Updates stores.vcode when generating a new VCode (ohm#9x4p2k7q).';


-- ============================================================
-- §3  Safe Data Repair for Existing Orphan Rows
-- ============================================================

-- A. Backfill plantilla_slots.store_id from vacancies.store_id (via legacy_vcode match)
UPDATE public.plantilla_slots ps
SET store_id = v.store_id,
    updated_at = now()
FROM public.vacancies v
WHERE ps.store_id IS NULL
  AND ps.legacy_vcode = v.vcode
  AND v.store_id IS NOT NULL;

-- B. Fallback: Backfill plantilla_slots.store_id from stores.id (via legacy_vcode match)
UPDATE public.plantilla_slots ps
SET store_id = s.id,
    updated_at = now()
FROM public.stores s
WHERE ps.store_id IS NULL
  AND ps.legacy_vcode = s.vcode;

-- C. Backfill stores.vcode from active non-pool vacancies where safe and unambiguous
-- (where the store has exactly one active vcode)
WITH unique_store_vacancies AS (
  SELECT store_id, MIN(vcode) AS active_vcode
  FROM public.vacancies
  WHERE store_id IS NOT NULL
    AND status IN ('Open', 'Pipeline')
    AND deleted_at IS NULL
    AND COALESCE(is_pool_vacancy, false) = false
  GROUP BY store_id
  HAVING COUNT(DISTINCT vcode) = 1
)
UPDATE public.stores s
SET vcode = usv.active_vcode
FROM unique_store_vacancies usv
WHERE s.id = usv.store_id
  AND (s.vcode IS NULL OR trim(s.vcode) = '');


-- ============================================================
-- §4  Verification Diagnostics (Queries in Comments)
-- ============================================================
-- 1. Check for any remaining active orphan slots:
--    SELECT count(*) as orphan_slots
--    FROM public.plantilla_slots
--    WHERE store_id IS NULL
--      AND slot_status <> 'closed';
--
-- 2. Verify target vacancy/store linkage:
--    SELECT v.vcode, v.store_id AS vacancy_store_id, s.id AS store_id, s.store_name, s.vcode AS store_vcode
--    FROM public.vacancies v
--    JOIN public.stores s ON s.id = v.store_id
--    WHERE upper(v.vcode) = 'VCTG2_0002';
--
-- 3. Verify slot linkage:
--    SELECT ps.id, ps.vcode, ps.store_id, s.store_name
--    FROM public.plantilla_slots ps
--    LEFT JOIN public.stores s ON s.id = ps.store_id
--    WHERE upper(ps.vcode) = 'VCTG2_0002';
--
-- 4. Verify SM Caloocan / VCTG2_0002 eligibility in get_coverage_group_eligible_stores:
--    SELECT * FROM public.get_coverage_group_eligible_stores(
--      (SELECT account_id FROM public.vacancies WHERE vcode = 'VCTG2_0002' LIMIT 1)
--    ) WHERE store_name ILIKE '%Caloocan%';

COMMIT;
