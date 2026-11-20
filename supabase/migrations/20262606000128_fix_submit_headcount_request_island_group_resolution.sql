-- ============================================================
-- Migration: 20262606000128_fix_submit_headcount_request_island_group_resolution.sql
-- Description:
--   Fix island group resolution for unlisted new stores in submit_headcount_request.
--   Replaces invalid queries against public.ref_locations (which does not have an
--   island_group column) and non-existent public.ref_provinces with the canonical
--   immutable database function public.fn_derive_island_group(p_province text).
-- ============================================================

BEGIN;

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

          -- Canonical island group derivation via fn_derive_island_group()
          v_new_ig := COALESCE(public.fn_derive_island_group(v_new_province), v_new_ig);

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

COMMIT;
