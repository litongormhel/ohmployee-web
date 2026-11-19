-- ============================================================
-- Migration: 20262606000126_roving_hc_new_stores_and_mandatory_justification.sql
-- Description:
--   ADR-003: Unified Roving Headcount Requisition with Atomic Store Provisioning
--   & Mandatory Operational Justification.
--   1. Upgrade public.hc_request_stores:
--      - Drop NOT NULL on store_id
--      - Add is_new_store, store_name, area_province, area_city, island_group, created_store_id
--      - Add check constraint chk_hc_request_stores_target
--   2. Update submit_headcount_request:
--      - Universal mandatory Operational Justification (>= 20 characters)
--      - Polymorphic store ingestion (support unlisted new store objects alongside store UUIDs)
--      - Island group validation across existing and proposed stores
--   3. Update create_plantilla_slot_from_request:
--      - Phase 1 atomic store provisioning: inserts unlisted stores into public.stores
--        strictly upon formal approval (zero premature database pollution)
--      - Phase 2 roving coverage group & VCode generation
--   4. Update get_hc_request_stores:
--      - Return is_new_store, store_name, province, city, island_group, created_store_id
-- ============================================================

BEGIN;

-- ── 1. Upgrade public.hc_request_stores ────────────────────────────────────────

ALTER TABLE public.hc_request_stores
  ALTER COLUMN store_id DROP NOT NULL;

ALTER TABLE public.hc_request_stores
  ADD COLUMN IF NOT EXISTS is_new_store boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS store_name text NULL,
  ADD COLUMN IF NOT EXISTS area_province text NULL,
  ADD COLUMN IF NOT EXISTS area_city text NULL,
  ADD COLUMN IF NOT EXISTS island_group text NULL,
  ADD COLUMN IF NOT EXISTS created_store_id uuid NULL REFERENCES public.stores(id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_hc_request_stores_target'
  ) THEN
    ALTER TABLE public.hc_request_stores
      ADD CONSTRAINT chk_hc_request_stores_target CHECK (
        (is_new_store = false AND store_id IS NOT NULL) OR
        (is_new_store = true AND (store_name IS NOT NULL OR store_name_snapshot IS NOT NULL))
      );
  END IF;
END $$;


-- ── 2. Update submit_headcount_request ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.submit_headcount_request(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role                  text := public.get_my_role();
  v_account               accounts%ROWTYPE;
  v_store                 stores%ROWTYPE;
  v_position              positions%ROWTYPE;
  v_group                 groups%ROWTYPE;
  v_coverage_group        coverage_groups%ROWTYPE;
  v_request_id            uuid;
  v_account_id            uuid;
  v_store_id              uuid;
  v_position_id           uuid;
  v_coverage_group_id     uuid;
  v_store_name            text;
  v_workforce_type        text;
  v_headcount_needed      integer;
  v_reason                text;
  -- store-array / roving path
  v_stores_raw            jsonb;
  v_elem                  jsonb;
  v_parsed_stores         jsonb := '[]'::jsonb;
  v_store_count           integer := 0;
  v_island_groups         text[];
  v_island_group          text;
  v_store_rec             stores%ROWTYPE;
  v_sort_order            integer := 0;
  v_source_nsr_id         uuid;
  -- new store metadata
  v_is_new_store          boolean;
  v_new_store_name        text;
  v_new_province          text;
  v_new_city              text;
  v_new_ig                text;
BEGIN
  IF NOT (public.i_have_full_access() OR public.i_am_ops()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  v_workforce_type := lower(nullif(trim(coalesce(
    p_input->>'workforce_type',
    p_input->>'employment_type',
    'stationary'
  )), ''));

  IF v_workforce_type NOT IN ('stationary', 'roving', 'floating') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_workforce_type');
  END IF;

  IF v_workforce_type = 'floating' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'floating_workforce_not_enabled',
      'message', 'Floating workforce is reserved for a future phase.'
    );
  END IF;

  -- ── Mandatory Operational Justification Guard (ADR-003: >= 20 characters) ───
  v_reason := trim(coalesce(p_input->>'reason', ''));
  IF length(v_reason) < 20 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'justification_required',
      'message', 'Operational justification is mandatory (minimum 20 characters).'
    );
  END IF;

  BEGIN
    v_account_id  := (p_input->>'account_id')::uuid;
    v_store_id    := nullif(trim(coalesce(p_input->>'store_id', '')), '')::uuid;
    v_position_id := (p_input->>'position_id')::uuid;
    v_coverage_group_id := nullif(trim(coalesce(p_input->>'coverage_group_id', '')), '')::uuid;
    v_headcount_needed := coalesce((p_input->>'headcount_needed')::int, 1);
    v_source_nsr_id := nullif(trim(coalesce(p_input->>'source_new_store_request_id', '')), '')::uuid;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN jsonb_build_object(
        'ok',    false,
        'error', 'invalid_reference',
        'field', 'uuid_cast',
        'detail', sqlerrm
      );
  END;

  -- ── HC Request idempotency guard (ohm#c3f9a8z1) ─────────────────────────
  IF v_source_nsr_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.headcount_requests
      WHERE source_new_store_request_id = v_source_nsr_id
        AND status IN ('pending', 'under_review')
    ) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'hc_request_already_pending',
        'message', 'A headcount request for this store is already pending.'
      );
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.headcount_requests
      WHERE source_new_store_request_id = v_source_nsr_id
        AND status IN ('approved_pending_vcode', 'completed')
    ) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'hc_request_already_approved',
        'message', 'This store already has an approved headcount request.'
      );
    END IF;
  END IF;

  -- ── Parse polymorphic stores array (ADR-003: supports store UUIDs & new store objects) ──
  v_stores_raw := COALESCE(p_input->'stores', p_input->'store_ids');
  IF v_stores_raw IS NOT NULL AND jsonb_typeof(v_stores_raw) = 'array' THEN
    FOR v_elem IN SELECT * FROM jsonb_array_elements(v_stores_raw)
    LOOP
      IF jsonb_typeof(v_elem) = 'string' THEN
        -- Plain UUID string
        IF nullif(trim(v_elem #>> '{}'), '') IS NOT NULL THEN
          v_parsed_stores := v_parsed_stores || jsonb_build_object(
            'is_new_store', false,
            'store_id', (v_elem #>> '{}')::uuid
          );
        END IF;
      ELSIF jsonb_typeof(v_elem) = 'object' THEN
        v_is_new_store := COALESCE((v_elem->>'is_new_store')::boolean, false)
                          OR (v_elem->>'store_id' IS NULL AND v_elem->>'id' IS NULL);
        IF v_is_new_store THEN
          v_new_store_name := nullif(trim(coalesce(v_elem->>'store_name', v_elem->>'name', '')), '');
          v_new_province   := nullif(trim(coalesce(v_elem->>'area_province', v_elem->>'province', '')), '');
          v_new_city       := nullif(trim(coalesce(v_elem->>'area_city', v_elem->>'city', '')), '');
          v_new_ig         := nullif(trim(coalesce(v_elem->>'island_group', '')), '');

          IF v_new_store_name IS NULL OR v_new_province IS NULL OR v_new_city IS NULL THEN
            RETURN jsonb_build_object(
              'ok', false,
              'error', 'invalid_new_store',
              'message', 'Store name, province, and city are required for all proposed new stores.'
            );
          END IF;

          IF v_new_ig IS NULL THEN
            SELECT island_group INTO v_new_ig
            FROM public.ref_locations
            WHERE lower(province) = lower(v_new_province)
              AND (city IS NULL OR lower(city) = lower(v_new_city))
              AND is_active = true
            LIMIT 1;

            IF v_new_ig IS NULL THEN
              SELECT island_group INTO v_new_ig
              FROM public.ref_provinces
              WHERE lower(province_name) = lower(v_new_province)
              LIMIT 1;
            END IF;
          END IF;

          v_parsed_stores := v_parsed_stores || jsonb_build_object(
            'is_new_store', true,
            'store_name', v_new_store_name,
            'area_province', v_new_province,
            'area_city', v_new_city,
            'island_group', v_new_ig
          );
        ELSE
          v_parsed_stores := v_parsed_stores || jsonb_build_object(
            'is_new_store', false,
            'store_id', (COALESCE(v_elem->>'store_id', v_elem->>'id'))::uuid
          );
        END IF;
      END IF;
    END LOOP;
  END IF;

  IF v_headcount_needed < 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_headcount_needed');
  END IF;

  SELECT * INTO v_account FROM public.accounts WHERE id = v_account_id;
  IF v_account.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'account_id');
  END IF;

  SELECT * INTO v_position FROM public.positions WHERE id = v_position_id;
  IF v_position.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'position_id');
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_account.account_name = ANY(public.get_my_allowed_accounts())) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'out_of_scope');
  END IF;

  IF v_workforce_type = 'stationary' THEN
    -- ── Stationary path ────────────────────────────────────────────────────
    IF v_store_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'store_required_for_stationary');
    END IF;

    SELECT * INTO v_store
    FROM public.stores
    WHERE id = v_store_id
      AND account_id = v_account_id
      AND coalesce(is_active, true) = true;

    IF v_store.id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'store_id');
    END IF;

    v_store_name := nullif(trim(v_store.store_name), '');
    IF v_store_name IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'store_name_required');
    END IF;

  ELSIF v_workforce_type = 'roving' THEN
    -- ── Roving: detect store-array path vs legacy coverage_group_id path ───
    v_store_count := jsonb_array_length(v_parsed_stores);

    IF v_store_count > 0 THEN
      -- ── Store-Array Path: requires >= 2 and <= 20 stores ──────────────────
      IF v_store_count < 2 THEN
        RETURN jsonb_build_object(
          'ok', false,
          'error', 'roving_requires_minimum_2_stores',
          'message', 'Roving HC Requests require at least 2 stores.'
        );
      END IF;

      IF v_store_count > 20 THEN
        RETURN jsonb_build_object(
          'ok', false,
          'error', 'roving_store_count_limit_exceeded',
          'message', 'Maximum 20 stores per roving HC Request.'
        );
      END IF;

      -- Validate stores and collect island groups
      v_island_groups := ARRAY[]::text[];

      FOR v_elem IN SELECT * FROM jsonb_array_elements(v_parsed_stores)
      LOOP
        IF (v_elem->>'is_new_store')::boolean = true THEN
          v_new_ig := v_elem->>'island_group';
          IF v_new_ig IS NOT NULL AND NOT (v_new_ig = ANY(v_island_groups)) THEN
            v_island_groups := array_append(v_island_groups, v_new_ig);
          END IF;
        ELSE
          v_store_id := (v_elem->>'store_id')::uuid;
          SELECT * INTO v_store_rec
          FROM public.stores
          WHERE id = v_store_id
            AND account_id = v_account_id
            AND coalesce(is_active, true) = true
            AND status = 'active';

          IF v_store_rec.id IS NULL THEN
            RETURN jsonb_build_object(
              'ok', false,
              'error', 'invalid_store',
              'store_id', v_store_id,
              'message', 'One or more selected stores are invalid, inactive, or outside scope.'
            );
          END IF;

          IF v_store_rec.island_group IS NOT NULL
             AND NOT (v_store_rec.island_group = ANY(v_island_groups)) THEN
            v_island_groups := array_append(v_island_groups, v_store_rec.island_group);
          END IF;
        END IF;
      END LOOP;

      -- ── Island group validation (HARD BLOCK) ────────────────────────────
      IF array_length(v_island_groups, 1) > 1 THEN
        RETURN jsonb_build_object(
          'ok', false,
          'error', 'island_group_span_violation',
          'island_groups', v_island_groups,
          'message',
            'Coverage Group cannot span multiple island groups. '
            'Create separate HC Requests per island group.'
        );
      END IF;

      v_island_group := CASE
        WHEN array_length(v_island_groups, 1) = 1 THEN v_island_groups[1]
        ELSE NULL
      END;

      v_store_id   := NULL;  -- store assignments reside in hc_request_stores
      v_store_name := NULL;

    ELSE
      -- ── Legacy path: coverage_group_id ──────────────────────────────────
      IF v_coverage_group_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'coverage_group_required_for_roving');
      END IF;

      SELECT * INTO v_coverage_group
      FROM public.coverage_groups
      WHERE id = v_coverage_group_id
        AND account_id = v_account_id
        AND archived_at IS NULL;

      IF v_coverage_group.id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'coverage_group_id');
      END IF;

      IF v_coverage_group.position_id <> v_position_id THEN
        RETURN jsonb_build_object('ok', false, 'error', 'coverage_group_position_mismatch');
      END IF;

      v_store_id   := NULL;
      v_store_name := v_coverage_group.coverage_code;
      v_island_group := NULL;
    END IF;
  END IF;

  SELECT * INTO v_group FROM public.groups WHERE id = v_account.group_id;

  INSERT INTO public.headcount_requests (
    account_id, store_id, position_id,
    employment_type, workforce_type, coverage_group_id, coverage_group_code_snapshot,
    area, city_municipality, request_type,
    headcount_needed, vacant_date, target_fill_date,
    urgency, reason,
    status,
    group_id, account_name_snapshot, store_name_snapshot,
    position_name_snapshot, group_name_snapshot,
    requested_by_user_id, requested_by_name, requested_by_role,
    island_group, source_new_store_request_id
  ) VALUES (
    v_account_id, v_store_id, v_position_id,
    coalesce(p_input->>'employment_type', initcap(v_workforce_type)),
    v_workforce_type,
    CASE WHEN v_workforce_type = 'roving' AND v_store_count = 0 THEN v_coverage_group_id ELSE NULL END,
    CASE WHEN v_workforce_type = 'roving' AND v_store_count = 0 THEN v_coverage_group.coverage_code ELSE NULL END,
    coalesce(p_input->>'area_province', p_input->>'area', v_coverage_group.area_name),
    nullif(trim(coalesce(p_input->>'area_city', '')), ''),
    coalesce(p_input->>'request_type', 'Replacement'),
    v_headcount_needed,
    nullif(p_input->>'vacant_date', '')::date,
    nullif(p_input->>'target_fill_date', '')::date,
    coalesce(p_input->>'urgency', 'Medium'),
    v_reason,
    'pending',
    v_account.group_id, v_account.account_name, v_store_name,
    v_position.position_name, v_group.group_name,
    public.get_current_profile_id(), public.get_my_full_name(), v_role,
    v_island_group, v_source_nsr_id
  ) RETURNING id INTO v_request_id;

  -- ── Insert hc_request_stores rows (ADR-003 polymorphic store ingestion) ──
  IF v_store_count > 0 THEN
    v_sort_order := 0;
    FOR v_elem IN SELECT * FROM jsonb_array_elements(v_parsed_stores)
    LOOP
      IF (v_elem->>'is_new_store')::boolean = true THEN
        INSERT INTO public.hc_request_stores (
          request_id, store_id, is_new_store,
          store_name, area_province, area_city, island_group,
          store_name_snapshot, province_snapshot, city_snapshot, island_group_snapshot,
          sort_order
        ) VALUES (
          v_request_id, NULL, true,
          v_elem->>'store_name', v_elem->>'area_province', v_elem->>'area_city', v_elem->>'island_group',
          v_elem->>'store_name', v_elem->>'area_province', v_elem->>'area_city', v_elem->>'island_group',
          v_sort_order
        );
      ELSE
        v_store_id := (v_elem->>'store_id')::uuid;
        SELECT * INTO v_store_rec FROM public.stores WHERE id = v_store_id;

        INSERT INTO public.hc_request_stores (
          request_id, store_id, is_new_store,
          store_name, area_province, area_city, island_group,
          store_name_snapshot, province_snapshot, city_snapshot, island_group_snapshot,
          sort_order
        ) VALUES (
          v_request_id, v_store_rec.id, false,
          v_store_rec.store_name, COALESCE(v_store_rec.province, v_store_rec.area_province), v_store_rec.area_city, v_store_rec.island_group,
          v_store_rec.store_name, COALESCE(v_store_rec.province, v_store_rec.area_province), v_store_rec.area_city, v_store_rec.island_group,
          v_sort_order
        );
      END IF;
      v_sort_order := v_sort_order + 1;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'ok',              true,
    'request_id',      v_request_id,
    'status',          'pending',
    'workforce_type',  v_workforce_type,
    'store_count',     v_store_count,
    'island_group',    v_island_group
  );
END
$function$;


-- ── 3. Update create_plantilla_slot_from_request ─────────────────────────────

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

        -- Create or adopt plantilla_slots for this store VCode
        IF NOT EXISTS (
          SELECT 1 FROM public.plantilla_slots WHERE legacy_vcode = v_vcode LIMIT 1
        ) THEN
          PERFORM public.fn_create_slots_from_hc_request(p_request_id, 1, v_vcode);
        END IF;

        UPDATE public.plantilla_slots
        SET store_id = v_hc_store_row.store_id
        WHERE legacy_vcode = v_vcode AND store_id IS NULL;

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


-- ── 4. Update get_hc_request_stores ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_hc_request_stores(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- Verify caller access (own request or full access or ops)
  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.headcount_requests
      WHERE id = p_request_id
        AND (
          requested_by_user_id = public.get_current_profile_id()
          OR public.i_am_ops()
        )
    ) THEN
      RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id',                   hrs.id,
      'store_id',             hrs.store_id,
      'store_name',           COALESCE(hrs.store_name, hrs.store_name_snapshot),
      'province',             COALESCE(hrs.area_province, hrs.province_snapshot),
      'city',                 COALESCE(hrs.area_city, hrs.city_snapshot),
      'island_group',         COALESCE(hrs.island_group, hrs.island_group_snapshot),
      'is_new_store',         COALESCE(hrs.is_new_store, false),
      'created_store_id',     hrs.created_store_id,
      'sort_order',           hrs.sort_order
    ) ORDER BY hrs.sort_order ASC
  ), '[]'::jsonb)
  INTO v_rows
  FROM public.hc_request_stores hrs
  WHERE hrs.request_id = p_request_id;

  RETURN v_rows;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_hc_request_stores(uuid) TO authenticated;

COMMIT;
