-- Migration: 20260708180000_sync_hc_request_vacancy_requirements
-- Created: 2026-07-08
-- Purpose: Close the permanent sync gap flagged in ohm#5rz2mkp8 — every future
--          approved HC Request (stationary path) now writes its own
--          vacancy_requirements row instead of relying solely on the one-time
--          backfill migration (20260708012728). Roving/coverage-group paths
--          are untouched (they RETURN before reaching the new block) — they
--          never participate in vacancy_requirements per ADR-001.
--
-- Smoke Tests:
-- S1: Approve + execute a test stationary HC request on staging via
--     approve_headcount_request() + create_plantilla_slot_from_request();
--     confirm a matching vacancy_requirements row appears with the correct
--     position_id and hc_needed via read-only SELECT.
-- S2: Re-run the same (now completed) request id through
--     create_plantilla_slot_from_request(); confirm it no-ops
--     (request_not_approved) and no duplicate vacancy_requirements row is
--     created — pre-existing status guard, unchanged by this migration.
-- S3: Approve a second HC request reusing the SAME vcode/vacancy with a
--     DIFFERENT position; confirm a second vacancy_requirements row is
--     created for that vacancy_id (not merged into the first position's row).
-- S4: Approve a second HC request reusing the SAME vcode/vacancy with the
--     SAME position; confirm the existing vacancy_requirements row's
--     hc_needed increments instead of a duplicate row being created.

BEGIN;

-- ── Step 1: traceability column (additive, nullable — no backfill here) ────
ALTER TABLE public.vacancy_requirements
  ADD COLUMN IF NOT EXISTS source_headcount_request_id uuid
    REFERENCES public.headcount_requests(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.vacancy_requirements.source_headcount_request_id IS
  'HC request that originally created this line item, when known. Nullable — legacy backfilled rows (20260708012728) have no HC request of origin.';

-- ── Step 2: wire the sync into the real HC-approval execution chain ────────
-- CREATE OR REPLACE public.create_plantilla_slot_from_request(uuid)
-- All pre-existing statements are byte-identical to the live function; the
-- only addition is the new block immediately after v_vacancy_id is resolved
-- in the stationary branch, before the Plantilla (VACANT SLOT) insert loop.
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
  -- ohm#8xk3vpc9: vacancy_requirements sync (stationary path only)
  v_vr_id              uuid;
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

          -- Sync this new VCode to public.stores.vcode (fix: ohm#9x4p2k7q)
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

      -- Sync this new VCode to public.stores.vcode (fix: ohm#9x4p2k7q)
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

    -- Sync this new VCode to public.stores.vcode (fix: ohm#9x4p2k7q)
    IF v_store_id IS NOT NULL THEN
      UPDATE public.stores
      SET vcode = v_vcode
      WHERE id = v_store_id
        AND (vcode IS NULL OR trim(vcode) = '');
    END IF;
  END IF;

  v_vcodes := ARRAY[v_vcode];

  -- ── ohm#8xk3vpc9: sync into vacancy_requirements (stationary path only) ───
  -- Merges into the existing (vacancy_id, position_id) row when one already
  -- exists (e.g. a second HC request reusing the same vcode for the SAME
  -- position); otherwise creates a fresh line item. Roving/coverage branches
  -- above always RETURN before this point, so they never reach it — matches
  -- ADR-001 (they are not vacancy_requirements participants). Wrapped in its
  -- own exception handler so a sync failure can never block the underlying
  -- HC-request completion (mirrors the pattern used by
  -- fn_maybe_auto_assign_sole_hrco).
  BEGIN
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

COMMIT;
