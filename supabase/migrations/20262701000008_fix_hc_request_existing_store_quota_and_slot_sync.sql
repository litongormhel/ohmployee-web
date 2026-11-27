-- ============================================================================
-- Migration: 20262701000008_fix_hc_request_existing_store_quota_and_slot_sync.sql
-- Module: Approvals / Plantilla / Vacancy (ADR-001 Core Rules 1 & 2, ADR-002 Invariants 1 & 2)
--
-- Root Causes Addressed:
--   1. Existing Store HC Expansion Quota Drop (`TEST002` — Super 2, BANKO):
--      In `public.create_plantilla_slot_from_request`, when approving an additional
--      stationary HC request on an existing baseline-imported store whose VCode
--      had no prior row in `public.vacancies`, the RPC inserted `required_headcount = v_count`
--      (e.g., 1) without adding the store's pre-existing active stationary slots (e.g., 1).
--      `vw_vacancy_list` therefore computed `hc_filled (1) >= hc_total (1)` -> `derived_status = 'Hired'`,
--      hiding the newly requested HC from Vacancy Open, Plantilla Vacancy Tab, and Store View Required/Vacancy.
--   2. Trigger Double-Slot & Wrong-Position Race (`VCCG1_0007`, `VCCG1_0008`):
--      Updating/inserting `public.vacancies` with increased `required_headcount` fired
--      `fn_trg_auto_create_vacancy_slot()`, which stamped slots with the old `NEW.position`
--      and `source_hc_request_id = NULL`, right before `fn_create_slots_from_hc_request()`
--      created a second set of slots with the requested position.
--      Fixed via transaction-local GUC `ohm.skip_auto_vacancy_slot` (preserving trigger
--      behavior for direct admin/import writes per ADR Core Slot-Creation Traceability).
--   3. Archived/Closed Store Re-Request Safety & `vacancy_requirements` Parity:
--      Look up existing `public.vacancies` by `vcode` regardless of `is_archived` so
--      standby/closed stores reactivate in-place without colliding on `vacancies_vcode_key`.
--      Backfill pre-existing active stationary store positions into `vacancy_requirements`
--      (and link active `plantilla.vacancy_requirement_id`) so `vw_vacancy_requirements`
--      and `vw_slot_derived_vacancy_shadow` stay 1:1 with `vacancies.required_headcount`.
--   4. Idempotent Data Repair:
--      Repairs `TEST002` (`required_headcount = 2`, `Merchandiser` requirement linked to
--      active occupant) and removes the 2 trigger-duplicated orphan slots on `VCCG1_0007`
--      and `VCCG1_0008` while backfilling their initial position requirements.
-- ============================================================================

BEGIN;

-- ── 1. Surgical update to fn_trg_auto_create_vacancy_slot ───────────────────
-- Base: live Staging definition (20262606000008_reassert_function_bodies.sql)
-- Surgical diff: honor transaction-local `ohm.skip_auto_vacancy_slot = 'on'`
-- when `create_plantilla_slot_from_request` is provisioning exact requested slots.
CREATE OR REPLACE FUNCTION public.fn_trg_auto_create_vacancy_slot()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- Allow authoritative HC request slot-provisioning RPC to own exact slot creation
  -- without racing against this trigger (prevents duplicate & wrong-position slots).
  IF current_setting('ohm.skip_auto_vacancy_slot', true) = 'on' THEN
    RETURN NEW;
  END IF;

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

  -- Resolve store_id, prioritizing NEW.store_id (fix: ohm#9x4p2k7q)
  -- Previously only did VCode lookup, causing NULL store_id for new stores
  -- where stores.vcode had not yet been set.
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

  -- ohm#5wq2n9tv: store_id is still unresolved after both attempts above.
  -- Do NOT raise — live data shows the large majority of import-created
  -- vacancies reference stores not yet registered in `stores`, so hard-
  -- failing here would block commit for the majority case, not an edge
  -- case. Flag it instead so the gap is visible/reportable.
  IF v_store_id IS NULL THEN
    INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
    VALUES (
      public.get_current_profile_id(),
      'vacancies',
      'UPDATE',
      NEW.id,
      jsonb_build_object('event', 'store_id_unresolved', 'vcode', NEW.vcode)
    );
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
      NEW.source_headcount_request_id,
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
END;
$function$;


-- ── 2. Surgical update to create_plantilla_slot_from_request ────────────────
-- Base: 20262606000193_fix_core_rpc_and_lifecycle_sync.sql (lines 1283-1943)
-- Surgical diff: stationary reused-VCODE quota accumulation, archived vacancy
-- in-place reactivation, trigger-race suppression, and pre-existing position
-- backfill into vacancy_requirements.
CREATE OR REPLACE FUNCTION public.create_plantilla_slot_from_request(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role                  text := public.get_my_role();
  v_req                   public.headcount_requests%ROWTYPE;
  v_account               public.accounts%ROWTYPE;
  v_store                 public.stores%ROWTYPE;
  v_position              public.positions%ROWTYPE;
  v_coverage_group        public.coverage_groups%ROWTYPE;
  v_store_name            text;
  v_store_id              uuid;
  v_vcode                 text;
  v_vcodes                text[];
  v_plantilla_id          uuid;
  v_vacancy_id            uuid;
  v_first_plantilla_id    uuid;
  v_count                 integer;
  i                       integer;
  v_triggered_by_id       uuid;
  v_triggered_by_name     text;
  v_hrco_user_id          uuid;
  v_hrco_name             text;
  v_group_id              uuid;
  v_group_name            text;
  v_slot_result           jsonb;
  v_max_ordinal           integer;
  -- store-array path
  v_hc_store_row          public.hc_request_stores%ROWTYPE;
  v_new_cg_id             uuid;
  v_cg_code               text;
  v_store_vcodes          jsonb := '[]'::jsonb;
  v_stores_added          integer := 0;
  v_store_row             public.stores%ROWTYPE;
  -- stationary path VCODE reuse fields
  v_reused_vcode          boolean := false;
  v_vr_id                 uuid;
  v_existing_active_slots integer := 0;
  v_existing_vac          public.vacancies%ROWTYPE;
  v_target_required_hc    integer;
  v_seed_slot             RECORD;
  v_seed_pos_id           uuid;
  v_seed_vr_id            uuid;
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

  -- Hard guard for position_id validity
  IF NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = v_req.position_id
  ) THEN
    RAISE EXCEPTION 'Invalid position_id: %', v_req.position_id;
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

    -- Check if this is the store-array path
    IF EXISTS (
      SELECT 1 FROM public.hc_request_stores WHERE request_id = p_request_id LIMIT 1
    ) THEN
      -- ══ ROVING STORE-ARRAY PATH (ADR-003 ATOMIC STORE PROVISIONING) ═════

      -- Step 1.5: Atomic Store Provisioning for unlisted/new stores in hc_request_stores
      FOR v_hc_store_row IN
        SELECT * FROM public.hc_request_stores
        WHERE request_id = p_request_id
          AND (is_new_store = true OR store_id IS NULL)
        ORDER BY sort_order ASC
      LOOP
        -- Check if an active store with the exact same name already exists in this account (idempotency guard)
        SELECT * INTO v_store_row
        FROM public.stores
        WHERE account_id = v_req.account_id
          AND lower(trim(store_name)) = lower(trim(COALESCE(v_hc_store_row.store_name, v_hc_store_row.store_name_snapshot)))
          AND coalesce(is_active, true) = true
        LIMIT 1;

        IF v_store_row.id IS NOT NULL THEN
          v_store_id := v_store_row.id;
        ELSE
          INSERT INTO public.stores (
            account_id,
            group_id,
            store_name,
            area_city,
            province,
            area_province,
            island_group,
            is_active,
            status,
            created_by,
            approved_by,
            approved_at
          ) VALUES (
            v_req.account_id,
            v_group_id,
            COALESCE(v_hc_store_row.store_name, v_hc_store_row.store_name_snapshot),
            COALESCE(v_hc_store_row.area_city, v_hc_store_row.city_snapshot),
            COALESCE(v_hc_store_row.area_province, v_hc_store_row.province_snapshot),
            COALESCE(v_hc_store_row.area_province, v_hc_store_row.province_snapshot),
            COALESCE(v_hc_store_row.island_group, v_hc_store_row.island_group_snapshot),
            true,
            'active',
            v_req.requested_by_user_id,
            v_triggered_by_id,
            now()
          ) RETURNING id INTO v_store_id;
        END IF;

        UPDATE public.hc_request_stores
        SET store_id = v_store_id,
            created_store_id = v_store_id
        WHERE id = v_hc_store_row.id;
      END LOOP;

      v_vcodes := ARRAY[]::text[];

      -- Step 1: Create the Coverage Group (structure only)
      v_new_cg_id := gen_random_uuid();
      v_cg_code   := public.fn_generate_cgcode_for_account(v_req.account_id);

      INSERT INTO public.coverage_groups (
        id,
        account_id,
        position_id,
        coverage_code,
        area_name,
        employment_type,
        status,
        required_headcount,
        created_by
      ) VALUES (
        v_new_cg_id,
        v_req.account_id,
        v_req.position_id,
        v_cg_code,
        COALESCE(v_req.area, ''),
        COALESCE(v_req.employment_type, 'Roving'),
        'open',
        v_count,
        v_triggered_by_id
      );

      -- Step 2: For each store in hc_request_stores, create VCode + Vacancy + Slot
      FOR v_hc_store_row IN
        SELECT * FROM public.hc_request_stores
        WHERE request_id = p_request_id
        ORDER BY sort_order ASC
      LOOP
        SELECT * INTO v_store_row FROM public.stores WHERE id = v_hc_store_row.store_id;

        -- Track highest existing ordinal on this VCODE before vacancy upsert (ohm#phase2-mixed-roving-hc)
        -- Reuse existing VCODE for store if active vacancy exists
        v_vcode := public.find_reusable_store_vcode(
          v_req.account_id,
          v_hc_store_row.store_id,
          COALESCE(v_hc_store_row.store_name, v_hc_store_row.store_name_snapshot)
        );

        IF v_vcode IS NULL THEN
          v_vcode := public.generate_vcode_for_account(v_req.account_id);

          -- Sync this new VCode to public.stores.vcode (fix: ohm#9x4p2k7q)
          IF v_hc_store_row.store_id IS NOT NULL THEN
            UPDATE public.stores
            SET vcode = v_vcode
            WHERE id = v_hc_store_row.store_id
              AND (vcode IS NULL OR trim(vcode) = '');
          END IF;
        END IF;

        v_vcodes := array_append(v_vcodes, v_vcode);

        SELECT COALESCE(MAX(slot_ordinal), 0)
        INTO v_max_ordinal
        FROM public.plantilla_slots
        WHERE legacy_vcode = v_vcode;

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
        )
        SELECT
          v_vcode,
          v_account.account_name,
          p.position_name,
          'Open',
          v_account.id,
          v_hc_store_row.store_id,
          p.id,
          v_group_id,
          COALESCE(v_hc_store_row.area_province, v_hc_store_row.province_snapshot, v_store_row.province, v_store_row.area_province),
          COALESCE(v_hc_store_row.store_name, v_hc_store_row.store_name_snapshot, v_store_row.store_name),
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
          COALESCE(v_hc_store_row.area_city, v_hc_store_row.city_snapshot, v_store_row.area_city),
          COALESCE(v_hc_store_row.area_province, v_hc_store_row.province_snapshot, v_store_row.province, v_store_row.area_province),
          v_store_row.store_branch,
          v_group_name, v_group_id,
          v_triggered_by_id, v_triggered_by_id
        FROM public.positions p
        WHERE p.id = v_req.position_id
        ON CONFLICT (vcode) DO UPDATE
          SET required_headcount = public.vacancies.required_headcount + 1,
              updated_by = v_triggered_by_id
        RETURNING id INTO v_vacancy_id;

        -- Create or adopt distinct roving plantilla_slots for this request (ohm#phase2-mixed-roving-hc)
        -- Never alters existing stationary slots (slot_ordinal <= v_max_ordinal).
        IF EXISTS (
          SELECT 1 FROM public.plantilla_slots
          WHERE legacy_vcode = v_vcode
            AND slot_ordinal > v_max_ordinal
          LIMIT 1
        ) THEN
          UPDATE public.plantilla_slots
          SET store_id             = COALESCE(store_id, v_hc_store_row.store_id),
              is_roving            = true,
              employment_type      = COALESCE(v_req.employment_type, 'Roving'),
              source_hc_request_id = p_request_id,
              updated_at           = now(),
              updated_by           = v_triggered_by_id
          WHERE legacy_vcode = v_vcode
            AND slot_ordinal > v_max_ordinal;
        ELSE
          IF NOT EXISTS (
            SELECT 1 FROM public.plantilla_slots
            WHERE legacy_vcode = v_vcode
              AND source_hc_request_id = p_request_id
            LIMIT 1
          ) THEN
            PERFORM public.fn_create_slots_from_hc_request(p_request_id, 1, v_vcode);
          END IF;

          UPDATE public.plantilla_slots
          SET store_id        = COALESCE(store_id, v_hc_store_row.store_id),
              is_roving       = true,
              employment_type = COALESCE(v_req.employment_type, 'Roving'),
              updated_at      = now(),
              updated_by      = v_triggered_by_id
          WHERE legacy_vcode = v_vcode
            AND source_hc_request_id = p_request_id;
        END IF;

        -- Add store to coverage_group_stores
        INSERT INTO public.coverage_group_stores (
          coverage_group_id,
          store_id,
          is_anchor,
          added_by
        ) VALUES (
          v_new_cg_id,
          v_hc_store_row.store_id,
          (v_stores_added = 0),
          v_triggered_by_id
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
      -- ══ OLD ROVING PATH: add coverage slots to existing CG ══
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

      IF v_coverage_group.position_id IS NOT NULL AND v_coverage_group.position_id <> v_req.position_id THEN
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

  -- ── 1-store-1-VCODE reuse check ───────────────────────────────────────────
  v_vcode := public.find_reusable_store_vcode(v_account.id, v_store_id, v_store_name);

  IF v_vcode IS NOT NULL THEN
    v_reused_vcode := true;

    -- Count pre-existing active non-roving stationary headcount on this VCode
    -- BEFORE mutating vacancies so baseline-imported stores keep their existing quota.
    SELECT GREATEST(
      (SELECT COUNT(*)::integer
       FROM public.plantilla_slots
       WHERE legacy_vcode = v_vcode
         AND COALESCE(is_roving, false) = false
         AND closed_at IS NULL
         AND slot_status IN ('open', 'pipeline', 'hr_processing', 'occupied')),
      (SELECT COUNT(*)::integer
       FROM public.plantilla
       WHERE vcode = v_vcode
         AND status = 'Active'
         AND COALESCE(deployment_type, 'Stationary') <> 'Roving'
         AND COALESCE(is_deleted, false) = false
         AND COALESCE(is_archived, false) = false)
    ) INTO v_existing_active_slots;

    -- Look up any existing vacancy by vcode (including archived/closed rows)
    -- to respect `vacancies_vcode_key` uniqueness and avoid duplicate-key crashes.
    SELECT * INTO v_existing_vac
    FROM public.vacancies
    WHERE vcode      = v_vcode
      AND deleted_at IS NULL
    ORDER BY COALESCE(is_archived, false) ASC, created_at DESC
    LIMIT 1;

    -- Suppress fn_trg_auto_create_vacancy_slot while this RPC updates/inserts
    -- public.vacancies; fn_create_slots_from_hc_request below creates the exact
    -- requested v_count slots with the exact requested position and traceability.
    PERFORM set_config('ohm.skip_auto_vacancy_slot', 'on', true);

    IF v_existing_vac.id IS NOT NULL THEN
      v_vacancy_id := v_existing_vac.id;

      IF COALESCE(v_existing_vac.is_archived, false) = true
         OR v_existing_vac.status IN ('Closed', 'Archived') THEN
        -- Reactivate previously archived/closed vacancy in-place with live quota
        v_target_required_hc := v_existing_active_slots + v_count;

        UPDATE public.vacancies
        SET required_headcount          = v_target_required_hc,
            status                      = 'Open',
            is_archived                 = false,
            archived_at                 = NULL,
            closed_at                   = NULL,
            position                    = v_position.position_name,
            position_id                 = v_position.id,
            vacant_date                 = COALESCE(v_req.vacant_date, CURRENT_DATE),
            target_fill_date            = COALESCE(v_req.target_fill_date, target_fill_date),
            urgency_level               = COALESCE(v_req.urgency, urgency_level),
            source_headcount_request_id = p_request_id,
            updated_by                  = v_triggered_by_id,
            updated_at                  = now()
        WHERE id = v_vacancy_id;

        -- Clear dead requirements from the prior closed cycle not held by active staff
        DELETE FROM public.vacancy_requirements
        WHERE vacancy_id = v_vacancy_id
          AND NOT EXISTS (
            SELECT 1 FROM public.plantilla p
            WHERE p.vacancy_requirement_id = public.vacancy_requirements.id
              AND p.status = 'Active'
              AND COALESCE(p.is_deleted, false) = false
          );
      ELSE
        -- Active existing vacancy: increment quota cleanly above existing slots
        v_target_required_hc := GREATEST(
          COALESCE(v_existing_vac.required_headcount, 0)::integer,
          v_existing_active_slots
        ) + v_count;

        UPDATE public.vacancies
        SET required_headcount = v_target_required_hc,
            status             = 'Open',
            updated_by         = v_triggered_by_id,
            updated_at         = now()
        WHERE id = v_vacancy_id;
      END IF;
    ELSE
      -- Baseline-imported store with existing active slots but no vacancies row yet:
      -- required_headcount MUST include pre-existing active slots + newly requested v_count.
      v_target_required_hc := v_existing_active_slots + v_count;

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
      )
      SELECT
        v_vcode, v_account.account_name, p.position_name, 'Open',
        v_account.id, v_store_id, p.id, v_group_id,
        COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
        v_store_name,
        COALESCE(v_req.vacant_date, CURRENT_DATE),
        v_target_required_hc,
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
      FROM public.positions p
      WHERE p.id = v_req.position_id
      RETURNING id INTO v_vacancy_id;

      -- Sync this new VCode to public.stores.vcode (fix: ohm#9x4p2k7q)
      IF v_store_id IS NOT NULL THEN
        UPDATE public.stores
        SET vcode = v_vcode
        WHERE id = v_store_id
          AND (vcode IS NULL OR trim(vcode) = '');
      END IF;
    END IF;

    PERFORM set_config('ohm.skip_auto_vacancy_slot', 'off', true);

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
    )
    SELECT
      v_vcode, v_account.account_name, p.position_name, 'Open',
      v_account.id, v_store_id, p.id, v_group_id,
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
    FROM public.positions p
    WHERE p.id = v_req.position_id
    RETURNING id INTO v_vacancy_id;

    -- Sync this new VCode to public.stores.vcode (fix: ohm#9x4p2k7q)
    IF v_store_id IS NOT NULL THEN
      UPDATE public.stores
      SET vcode = v_vcode
      WHERE id = v_store_id
        AND (vcode IS NULL OR trim(vcode) = '');
    END IF;
  END IF;

  v_vcodes := ARRAY[v_vcode];

  BEGIN
    -- Seed pre-existing active stationary store positions into vacancy_requirements
    -- before adding the newly requested position so SUM(hc_needed) matches
    -- vacancies.required_headcount and occupied positions resolve as Full in vw_vacancy_requirements.
    IF v_reused_vcode
       AND v_existing_active_slots > 0
       AND NOT EXISTS (
         SELECT 1 FROM public.vacancy_requirements WHERE vacancy_id = v_vacancy_id
       ) THEN
      FOR v_seed_slot IN
        SELECT
          btrim(ps.position) AS pos_name,
          COALESCE(NULLIF(btrim(MIN(ps.employment_type)), ''), 'Stationary') AS emp_type,
          COUNT(*)::integer AS slot_cnt
        FROM public.plantilla_slots ps
        WHERE ps.legacy_vcode = v_vcode
          AND COALESCE(ps.is_roving, false) = false
          AND ps.closed_at IS NULL
          AND ps.slot_status IN ('open', 'pipeline', 'hr_processing', 'occupied')
          AND NULLIF(btrim(ps.position), '') IS NOT NULL
        GROUP BY btrim(ps.position)
      LOOP
        SELECT p.id INTO v_seed_pos_id
        FROM public.positions p
        WHERE lower(btrim(p.position_name)) = lower(v_seed_slot.pos_name)
        LIMIT 1;

        IF v_seed_pos_id IS NOT NULL THEN
          INSERT INTO public.vacancy_requirements (
            vacancy_id, position_id, employment_type, hc_needed, hc_filled
          ) VALUES (
            v_vacancy_id, v_seed_pos_id, v_seed_slot.emp_type, v_seed_slot.slot_cnt, 0
          )
          RETURNING id INTO v_seed_vr_id;

          UPDATE public.plantilla
          SET vacancy_requirement_id = v_seed_vr_id
          WHERE vcode = v_vcode
            AND status = 'Active'
            AND COALESCE(deployment_type, 'Stationary') <> 'Roving'
            AND COALESCE(is_deleted, false) = false
            AND COALESCE(is_archived, false) = false
            AND vacancy_requirement_id IS NULL
            AND (
              position_id = v_seed_pos_id
              OR lower(btrim(COALESCE(position, ''))) = lower(v_seed_slot.pos_name)
            );
        END IF;
      END LOOP;
    END IF;

    SELECT id INTO v_vr_id
    FROM public.vacancy_requirements
    WHERE vacancy_id = v_vacancy_id
      AND position_id = v_position.id
    FOR UPDATE;

    IF v_vr_id IS NOT NULL THEN
      UPDATE public.vacancy_requirements
      SET hc_needed = hc_needed + v_count
      WHERE id = v_vr_id;
    ELSE
      INSERT INTO public.vacancy_requirements (
        vacancy_id, position_id, employment_type, hc_needed, hc_filled,
        source_headcount_request_id
      ) VALUES (
        v_vacancy_id, v_position.id, v_req.employment_type, v_count, 0,
        p_request_id
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'vacancy_requirements sync failed for request % (vacancy %, position %): %',
      p_request_id, v_vacancy_id, v_position.id, SQLERRM;
  END;

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

  IF v_reused_vcode THEN
    v_slot_result := public.fn_create_slots_from_hc_request(p_request_id, v_count, v_vcode);
  ELSE
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
  END IF;

  UPDATE public.headcount_requests
  SET status                  = 'completed',
  vacancy_created             = true,
  slot_created_by_user_id     = v_triggered_by_id,
  slot_created_at             = NOW(),
  created_plantilla_id        = v_first_plantilla_id,
  created_vcode               = v_vcode,
  created_vcodes              = v_vcodes
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


-- ── 3. Idempotent Staging Data Repair ───────────────────────────────────────
DO $$
DECLARE
  v_vac_id       uuid;
  v_pos_id       uuid;
  v_vr_id        uuid;
  v_slot_cnt     integer;
  v_dup_slot_id  uuid;
BEGIN
  PERFORM set_config('ohm.skip_auto_vacancy_slot', 'on', true);

  -- 3A. Repair TEST002 (Super 2, BANKO):
  --     Sync required_headcount to live active stationary slots (2) and seed
  --     occupied Merchandiser requirement linked to active plantilla occupant.
  SELECT id INTO v_vac_id
  FROM public.vacancies
  WHERE vcode = 'TEST002'
    AND deleted_at IS NULL
  LIMIT 1;

  IF v_vac_id IS NOT NULL THEN
    SELECT COUNT(*)::integer INTO v_slot_cnt
    FROM public.plantilla_slots
    WHERE legacy_vcode = 'TEST002'
      AND COALESCE(is_roving, false) = false
      AND closed_at IS NULL
      AND slot_status IN ('open', 'pipeline', 'hr_processing', 'occupied');

    IF v_slot_cnt > 1 THEN
      UPDATE public.vacancies
      SET required_headcount = GREATEST(COALESCE(required_headcount, 1), v_slot_cnt),
          status             = 'Open',
          is_archived        = false,
          updated_at         = now()
      WHERE id = v_vac_id
        AND COALESCE(required_headcount, 1) < v_slot_cnt;
    END IF;

    SELECT id INTO v_pos_id
    FROM public.positions
    WHERE lower(btrim(position_name)) = 'merchandiser'
    LIMIT 1;

    IF v_pos_id IS NOT NULL THEN
      SELECT id INTO v_vr_id
      FROM public.vacancy_requirements
      WHERE vacancy_id = v_vac_id
        AND position_id = v_pos_id
      LIMIT 1;

      IF v_vr_id IS NULL THEN
        INSERT INTO public.vacancy_requirements (
          vacancy_id, position_id, employment_type, hc_needed, hc_filled
        ) VALUES (
          v_vac_id, v_pos_id, 'Stationary', 1, 0
        )
        RETURNING id INTO v_vr_id;
      END IF;

      UPDATE public.plantilla
      SET vacancy_requirement_id = v_vr_id
      WHERE vcode = 'TEST002'
        AND status = 'Active'
        AND COALESCE(is_deleted, false) = false
        AND COALESCE(is_archived, false) = false
        AND vacancy_requirement_id IS NULL
        AND (position_id = v_pos_id OR lower(btrim(COALESCE(position, ''))) = 'merchandiser');
    END IF;
  END IF;

  -- 3B. Repair trigger-duplicated orphan open slots on VCCG1_0007 & VCCG1_0008
  --     (only if still open, unoccupied, unlinked to applicants/hr_emploc, and source_hc_request_id IS NULL)
  FOREACH v_dup_slot_id IN ARRAY ARRAY[
    '61a99f37-ee56-4d82-b7d6-0bff15e204f9'::uuid,
    'cb0ecb0c-6932-43c3-838c-5fdd980ce52a'::uuid
  ] LOOP
    IF EXISTS (
      SELECT 1
      FROM public.plantilla_slots ps
      WHERE ps.id = v_dup_slot_id
        AND ps.slot_status = 'open'
        AND ps.current_occupant_plantilla_id IS NULL
        AND ps.source_hc_request_id IS NULL
        AND NOT EXISTS (SELECT 1 FROM public.applicants a WHERE a.slot_id = ps.id)
        AND NOT EXISTS (SELECT 1 FROM public.hr_emploc h WHERE h.slot_id = ps.id)
    ) THEN
      DELETE FROM public.slot_history WHERE slot_id = v_dup_slot_id;
      DELETE FROM public.plantilla_slots WHERE id = v_dup_slot_id;
    END IF;
  END LOOP;

  -- Renumber ordinal 3 -> 2 on VCCG1_0007 and VCCG1_0008 if ordinal 2 is now vacant
  IF NOT EXISTS (
    SELECT 1 FROM public.plantilla_slots WHERE legacy_vcode = 'VCCG1_0007' AND slot_ordinal = 2
  ) THEN
    UPDATE public.plantilla_slots
    SET slot_ordinal = 2, updated_at = now()
    WHERE id = 'fdadec3f-157c-44b9-a78d-b06d7ee833fb'::uuid
      AND legacy_vcode = 'VCCG1_0007'
      AND slot_ordinal = 3;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.plantilla_slots WHERE legacy_vcode = 'VCCG1_0008' AND slot_ordinal = 2
  ) THEN
    UPDATE public.plantilla_slots
    SET slot_ordinal = 2, updated_at = now()
    WHERE id = 'bfd7af7e-377b-4ada-a190-f8f81966ba37'::uuid
      AND legacy_vcode = 'VCCG1_0008'
      AND slot_ordinal = 3;
  END IF;

  -- Backfill initial slot #1 position into vacancy_requirements for VCCG1_0007 (Merchandiser)
  SELECT id INTO v_vac_id FROM public.vacancies WHERE vcode = 'VCCG1_0007' AND deleted_at IS NULL LIMIT 1;
  SELECT id INTO v_pos_id FROM public.positions WHERE lower(btrim(position_name)) = 'merchandiser' LIMIT 1;
  IF v_vac_id IS NOT NULL AND v_pos_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.vacancy_requirements WHERE vacancy_id = v_vac_id AND position_id = v_pos_id) THEN
    INSERT INTO public.vacancy_requirements (vacancy_id, position_id, employment_type, hc_needed, hc_filled)
    VALUES (v_vac_id, v_pos_id, 'Stationary', 1, 0);
  END IF;

  -- Backfill initial slot #1 position into vacancy_requirements for VCCG1_0008 (Counter Sales Personnel)
  SELECT id INTO v_vac_id FROM public.vacancies WHERE vcode = 'VCCG1_0008' AND deleted_at IS NULL LIMIT 1;
  SELECT id INTO v_pos_id FROM public.positions WHERE lower(btrim(position_name)) = 'counter sales personnel' LIMIT 1;
  IF v_vac_id IS NOT NULL AND v_pos_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.vacancy_requirements WHERE vacancy_id = v_vac_id AND position_id = v_pos_id) THEN
    INSERT INTO public.vacancy_requirements (vacancy_id, position_id, employment_type, hc_needed, hc_filled)
    VALUES (v_vac_id, v_pos_id, 'Stationary', 1, 0);
  END IF;

  PERFORM set_config('ohm.skip_auto_vacancy_slot', 'off', true);
END $$;

COMMIT;
