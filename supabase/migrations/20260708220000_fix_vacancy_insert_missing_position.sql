-- Migration: 20260708220000_fix_vacancy_insert_missing_position.sql
-- Description: Enforce position name hydration and validity guards before insert into public.vacancies.

-- 1. create_vacancy_from_headcount_request
CREATE OR REPLACE FUNCTION public.create_vacancy_from_headcount_request(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role              text := public.get_my_role();
  v_req               headcount_requests%ROWTYPE;
  v_account           accounts%ROWTYPE;
  v_store             stores%ROWTYPE;
  v_position          positions%ROWTYPE;
  v_store_name        text;
  v_store_id          uuid;
  v_group_id          uuid;
  v_group_name        text;
  v_triggered_by_id   uuid;
  v_triggered_by_name text;
  v_hrco_user_id      uuid;
  v_hrco_name         text;
BEGIN
  IF NOT (v_role IN ('Encoder', 'Super Admin', 'Head Admin')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  -- Enforce Recruitment Freeze
  PERFORM public.fn_assert_freeze_inactive('recruitment_freeze');

  SELECT * INTO v_req FROM public.headcount_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;
  IF v_req.status <> 'completed' THEN
    RETURN jsonb_build_object(
      'ok', false, 'error', 'request_not_completed', 'current', v_req.status
    );
  END IF;
  IF v_req.created_vcode IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_vcode_generated');
  END IF;
  IF coalesce(v_req.vacancy_created, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vacancy_already_created');
  END IF;

  -- Hard guard for position_id validity
  IF NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = v_req.position_id
  ) THEN
    RAISE EXCEPTION 'Invalid position_id: %', v_req.position_id;
  END IF;

  SELECT * INTO v_account  FROM public.accounts  WHERE id = v_req.account_id;
  SELECT * INTO v_position FROM public.positions WHERE id = v_req.position_id;

  IF v_req.store_id IS NOT NULL THEN
    SELECT * INTO v_store FROM public.stores WHERE id = v_req.store_id;
  END IF;
  v_store_name := COALESCE(v_store.store_name, v_req.store_name_snapshot);
  v_store_id   := v_store.id;

  v_group_id := COALESCE(v_req.group_id, v_account.group_id);
  SELECT group_name INTO v_group_name FROM public.groups WHERE id = v_group_id;

  v_triggered_by_id := public.get_current_profile_id();
  SELECT full_name INTO v_triggered_by_name
  FROM public.users_profile WHERE id = v_triggered_by_id;

  v_hrco_user_id := v_account.hrco_user_id;
  IF v_hrco_user_id IS NOT NULL THEN
    SELECT full_name INTO v_hrco_name
    FROM public.users_profile WHERE id = v_hrco_user_id;
  END IF;

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
    v_req.created_vcode, v_account.account_name, p.position_name, 'Open',
    v_account.id, v_store_id, p.id, v_group_id,
    COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province), v_store_name, COALESCE(v_req.vacant_date, CURRENT_DATE),
    v_req.headcount_needed, v_req.created_plantilla_id,
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
  WHERE p.id = v_req.position_id;

  UPDATE public.headcount_requests
  SET vacancy_created = true
  WHERE id = p_request_id;

  PERFORM public.log_audit_event(
    'Vacancy.CreatedFromHCRequest', 'INSERT', p_request_id,
    NULL,
    jsonb_build_object(
      'request_id', p_request_id,
      'vcode',      v_req.created_vcode,
      'account_id', v_req.account_id
    )
  );

  RETURN jsonb_build_object(
    'ok',              true,
    'request_id',      p_request_id,
    'vcode',           v_req.created_vcode,
    'vacancy_created', true
  );
END;
$function$;

-- 2. create_plantilla_slot_from_request
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
  v_hc_store_row       public.hc_request_stores%ROWTYPE;
  v_new_cg_id          uuid;
  v_cg_code            text;
  v_store_vcodes       jsonb := '[]'::jsonb;
  v_stores_added       integer := 0;
  v_store_row          public.stores%ROWTYPE;
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

  IF lower(coalesce(v_req.workforce_type, 'stationary')) = 'roving' THEN

    IF EXISTS (
      SELECT 1 FROM public.hc_request_stores WHERE request_id = p_request_id LIMIT 1
    ) THEN
      v_vcodes := ARRAY[]::text[];

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

      FOR v_hc_store_row IN
        SELECT * FROM public.hc_request_stores
        WHERE request_id = p_request_id
        ORDER BY sort_order ASC
      LOOP
        SELECT * INTO v_store_row FROM public.stores WHERE id = v_hc_store_row.store_id;

        v_vcode := public.find_reusable_store_vcode(v_req.account_id, v_hc_store_row.store_id, v_hc_store_row.store_name_snapshot);

        IF v_vcode IS NULL THEN
          v_vcode := public.generate_vcode_for_account(v_req.account_id);

          IF v_hc_store_row.store_id IS NOT NULL THEN
            UPDATE public.stores
            SET vcode = v_vcode
            WHERE id = v_hc_store_row.store_id
              AND (vcode IS NULL OR trim(vcode) = '');
          END IF;
        END IF;

        v_vcodes := array_append(v_vcodes, v_vcode);

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
          COALESCE(v_hc_store_row.province_snapshot, v_store_row.province, v_store_row.area_province),
          v_hc_store_row.store_name_snapshot,
          COALESCE(v_req.vacant_date, CURRENT_DATE),
          1,
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
        FROM public.positions p
        WHERE p.id = v_req.position_id
        ON CONFLICT (vcode) DO UPDATE
          SET required_headcount = public.vacancies.required_headcount + 1,
              updated_by = v_triggered_by_id
        RETURNING id INTO v_vacancy_id;

        IF NOT EXISTS (
          SELECT 1 FROM public.plantilla_slots WHERE legacy_vcode = v_vcode LIMIT 1
        ) THEN
          PERFORM public.fn_create_slots_from_hc_request(p_request_id, 1, v_vcode);
        END IF;

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

      SELECT COALESCE(MAX(slot_ordinal), 0)
        INTO v_max_ordinal
      FROM public.coverage_slots
      WHERE coverage_group_id = v_new_cg_id;

      INSERT INTO public.coverage_slots (coverage_group_id, slot_ordinal, slot_status)
      SELECT v_new_cg_id, v_max_ordinal + gs.ord, 'open'
      FROM generate_series(1, v_count) AS gs(ord);

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

  IF lower(coalesce(v_req.workforce_type, 'stationary')) = 'floating' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'floating_workforce_not_enabled');
  END IF;

  IF v_req.store_id IS NOT NULL THEN
    SELECT * INTO v_store FROM public.stores WHERE id = v_req.store_id;
  END IF;

  v_store_name := NULLIF(TRIM(COALESCE(v_store.store_name, v_req.store_name_snapshot)), '');
  v_store_id   := v_store.id;

  IF v_store_name IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'store_name');
  END IF;

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

-- 3. create_pool_vacancy
CREATE OR REPLACE FUNCTION public.create_pool_vacancy(p_pool_type_code text, p_position_id uuid, p_requesting_account_id uuid, p_requesting_store_id uuid DEFAULT NULL::uuid, p_headcount_needed integer DEFAULT 1, p_priority text DEFAULT 'normal'::text, p_reason text DEFAULT NULL::text, p_request_type text DEFAULT 'Additional'::text, p_province text DEFAULT NULL::text, p_city text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role_level            int;
  v_caller_id             uuid;
  v_caller_name           text;
  v_pool_type_id          uuid;
  v_moses_hq_id           uuid;
  v_requesting_acct_name  text;
  v_requesting_store_name text;
  v_position_name         text;
  v_req_group_id          uuid;
  v_req_group_name        text;
  v_pool_request_id       uuid;
  v_vcode                 text;
  v_vacancy_id            uuid;
  i                       int;
  v_is_ops_request        boolean;
BEGIN
  v_role_level := public.get_my_role_level();
  IF v_role_level IS NULL OR v_role_level NOT IN (100, 90, 70, 45, 42, 41, 40, 30) THEN
    RAISE EXCEPTION 'Unauthorized: create_pool_vacancy requires Data Team or Ops access';
  END IF;

  v_is_ops_request := (v_role_level BETWEEN 40 AND 70);
  v_caller_id      := auth.uid();
  v_caller_name    := public.get_my_full_name();

  IF p_headcount_needed < 1 OR p_headcount_needed > 50 THEN
    RAISE EXCEPTION 'headcount_needed must be 1–50, got %', p_headcount_needed;
  END IF;
  IF p_priority NOT IN ('normal', 'urgent', 'critical') THEN
    RAISE EXCEPTION 'Invalid priority: %', p_priority;
  END IF;
  IF p_request_type NOT IN ('Additional', 'Replacement') THEN
    RAISE EXCEPTION 'Invalid request_type: %. Must be Additional or Replacement', p_request_type;
  END IF;

  -- Hard guard for position_id validity
  IF NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = p_position_id
  ) THEN
    RAISE EXCEPTION 'Invalid position_id: %', p_position_id;
  END IF;

  SELECT id INTO v_pool_type_id
  FROM public.workforce_pool_types
  WHERE code = p_pool_type_code AND is_active = true;
  IF v_pool_type_id IS NULL THEN
    RAISE EXCEPTION 'Invalid pool type code: %', p_pool_type_code;
  END IF;

  SELECT id INTO v_moses_hq_id
  FROM public.accounts
  WHERE is_pool_account = true AND is_active = true
  LIMIT 1;
  IF v_moses_hq_id IS NULL THEN
    RAISE EXCEPTION 'Moses HQ pool account not found';
  END IF;

  SELECT a.account_name, a.group_id, g.group_name
  INTO   v_requesting_acct_name, v_req_group_id, v_req_group_name
  FROM   public.accounts a
  LEFT   JOIN public.groups g ON g.id = a.group_id
  WHERE  a.id = p_requesting_account_id AND a.is_active = true;
  IF v_requesting_acct_name IS NULL THEN
    RAISE EXCEPTION 'Requesting account not found or inactive';
  END IF;

  IF p_requesting_store_id IS NOT NULL THEN
    SELECT store_name INTO v_requesting_store_name
    FROM public.stores
    WHERE id = p_requesting_store_id AND is_active = true;
  END IF;

  SELECT position_name INTO v_position_name
  FROM public.positions
  WHERE id = p_position_id AND is_active = true;
  IF v_position_name IS NULL THEN
    RAISE EXCEPTION 'Position not found or inactive';
  END IF;

  -- ── Ops path: pending request — no vacancy yet ───────────────────────────
  IF v_is_ops_request THEN
    INSERT INTO public.workforce_pool_requests (
      pool_type_id, requesting_account_id, requesting_account,
      requesting_store_id, requesting_store,
      headcount_needed, priority, reason,
      status, created_by, created_by_name,
      position_id, position_name, is_ops_request, request_type,
      operational_account_id, operational_account_name,
      operational_group_id,   operational_group_name,
      is_global_pool_request,
      requested_province, requested_city
    ) VALUES (
      v_pool_type_id, p_requesting_account_id, v_requesting_acct_name,
      p_requesting_store_id, v_requesting_store_name,
      p_headcount_needed, p_priority, p_reason,
      'pending', v_caller_id::text, v_caller_name,
      p_position_id, v_position_name, true, p_request_type,
      p_requesting_account_id, v_requesting_acct_name,
      v_req_group_id, v_req_group_name,
      false,
      p_province, p_city
    ) RETURNING id INTO v_pool_request_id;

    RETURN jsonb_build_object(
      'success',           true,
      'pool_request_id',   v_pool_request_id,
      'pool_type',         p_pool_type_code,
      'headcount_created', p_headcount_needed,
      'vacancy_created',   false,
      'vcodes',            ARRAY[]::text[],
      'vacancy_ids',       ARRAY[]::uuid[]
    );
  END IF;

  -- ── Data Team path: auto-approved ──
  INSERT INTO public.workforce_pool_requests (
    pool_type_id, requesting_account_id, requesting_account,
    requesting_store_id, requesting_store,
    headcount_needed, priority, reason,
    status, approved_by, approved_at, created_by, created_by_name,
    position_id, position_name, is_ops_request, request_type,
    is_global_pool_request,
    requested_province, requested_city
  ) VALUES (
    v_pool_type_id, p_requesting_account_id, v_requesting_acct_name,
    p_requesting_store_id, v_requesting_store_name,
    p_headcount_needed, p_priority, p_reason,
    'approved', v_caller_name, now(), v_caller_id::text, v_caller_name,
    p_position_id, v_position_name, false, p_request_type,
    true,
    p_province, p_city
  ) RETURNING id INTO v_pool_request_id;

  v_vcode := public.generate_pool_vcode(p_pool_type_code);

  INSERT INTO public.vacancies (
    vcode, account, account_id, group_id,
    position, position_id, store_id,
    status, vacant_date, required_headcount, source,
    is_pool_vacancy, pool_type_id, home_account_id,
    affects_required_hc, affects_mfr, pool_request_id,
    created_by, is_ops_request,
    province, area_city
  )
  SELECT
    v_vcode, v_requesting_acct_name, p_requesting_account_id, v_req_group_id,
    p.position_name, p.id, p_requesting_store_id,
    'Open', now(), p_headcount_needed, 'pool',
    true, v_pool_type_id, v_moses_hq_id,
    false, false, v_pool_request_id,
    v_caller_id, false,
    p_province, p_city
  FROM public.positions p
  WHERE p.id = p_position_id
  RETURNING id INTO v_vacancy_id;

  FOR i IN 1..p_headcount_needed LOOP
    INSERT INTO public.workforce_pool_slots (
      vcode, pool_type_id, vacancy_id,
      status, account, account_id, group_id, created_by
    ) VALUES (
      v_vcode, v_pool_type_id, v_vacancy_id,
      'open', v_requesting_acct_name, p_requesting_account_id,
      v_req_group_id, v_caller_id
    );
  END LOOP;

  INSERT INTO public.workforce_pool_request_items (
    request_id, vacancy_id, vcode, position_id, status
  ) VALUES (
    v_pool_request_id, v_vacancy_id, v_vcode, p_position_id, 'open'
  );

  RETURN jsonb_build_object(
    'success',           true,
    'pool_request_id',   v_pool_request_id,
    'pool_type',         p_pool_type_code,
    'headcount_created', p_headcount_needed,
    'vacancy_created',   true,
    'vcodes',            ARRAY[v_vcode],
    'vacancy_ids',       ARRAY[v_vacancy_id]
  );
END;
$function$;

-- 4. approve_pool_vacancy_request
CREATE OR REPLACE FUNCTION public.approve_pool_vacancy_request(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role_level     int;
  v_caller_id      uuid;
  v_caller_name    text;
  v_req            public.workforce_pool_requests%ROWTYPE;
  v_pool_type_code text;
  v_moses_hq_id    uuid;
  v_vcode          text;
  v_vacancy_id     uuid;
  v_req_group_id   uuid;
  v_req_group_name text;
  i                int;
BEGIN
  v_role_level := public.get_my_role_level();
  IF v_role_level IS NULL OR v_role_level NOT IN (100, 90, 30) THEN
    RAISE EXCEPTION 'Unauthorized: approve_pool_vacancy_request requires Data Team/Admin access';
  END IF;

  v_caller_id   := auth.uid();
  v_caller_name := public.get_my_full_name();

  SELECT * INTO v_req
  FROM public.workforce_pool_requests
  WHERE id = p_request_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pool request not found: %', p_request_id;
  END IF;
  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'Request is already processed: status is %', v_req.status;
  END IF;

  -- Hard guard for position_id validity
  IF NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = v_req.position_id
  ) THEN
    RAISE EXCEPTION 'Invalid position_id: %', v_req.position_id;
  END IF;

  SELECT code INTO v_pool_type_code
  FROM public.workforce_pool_types
  WHERE id = v_req.pool_type_id;

  SELECT id INTO v_moses_hq_id
  FROM public.accounts
  WHERE is_pool_account = true AND is_active = true
  LIMIT 1;

  -- Resolve group from the requesting account.
  SELECT a.group_id, g.group_name
  INTO   v_req_group_id, v_req_group_name
  FROM   public.accounts a
  LEFT   JOIN public.groups g ON g.id = a.group_id
  WHERE  a.id = v_req.requesting_account_id AND a.is_active = true;

  v_vcode := public.generate_pool_vcode(v_pool_type_code);

  INSERT INTO public.vacancies (
    vcode, account, account_id, group_id,
    position, position_id, store_id,
    status, vacant_date, required_headcount, source,
    is_pool_vacancy, pool_type_id, home_account_id,
    affects_required_hc, affects_mfr, pool_request_id,
    created_by, is_ops_request,
    province, area_city
  )
  SELECT
    v_vcode, v_req.requesting_account, v_req.requesting_account_id, v_req_group_id,
    p.position_name, p.id, v_req.requesting_store_id,
    'Open', now(), v_req.headcount_needed, 'pool',
    true, v_req.pool_type_id, v_moses_hq_id,
    false, false, v_req.id,
    v_req.created_by::uuid, true,
    v_req.requested_province, v_req.requested_city
  FROM public.positions p
  WHERE p.id = v_req.position_id
  RETURNING id INTO v_vacancy_id;

  FOR i IN 1..v_req.headcount_needed LOOP
    INSERT INTO public.workforce_pool_slots (
      vcode, pool_type_id, vacancy_id,
      status, account, account_id, group_id, created_by
    ) VALUES (
      v_vcode, v_req.pool_type_id, v_vacancy_id,
      'open', v_req.requesting_account, v_req.requesting_account_id,
      v_req_group_id, v_req.created_by::uuid
    );
  END LOOP;

  INSERT INTO public.workforce_pool_request_items (
    request_id, vacancy_id, vcode, position_id, status
  ) VALUES (
    v_req.id, v_vacancy_id, v_vcode, v_req.position_id, 'open'
  );

  UPDATE public.workforce_pool_requests
  SET status                   = 'approved',
      approved_by              = v_caller_name,
      approved_at              = now(),
      updated_by               = v_caller_id::text,
      updated_at               = now(),
      operational_account_id   = COALESCE(operational_account_id,
                                   CASE WHEN is_ops_request
                                        THEN v_req.requesting_account_id
                                        ELSE NULL END),
      operational_account_name = COALESCE(operational_account_name,
                                   CASE WHEN is_ops_request
                                        THEN v_req.requesting_account
                                        ELSE NULL END),
      operational_group_id     = COALESCE(operational_group_id,
                                   CASE WHEN is_ops_request
                                        THEN v_req_group_id
                                        ELSE NULL END),
      operational_group_name   = COALESCE(operational_group_name,
                                   CASE WHEN is_ops_request
                                        THEN v_req_group_name
                                        ELSE NULL END)
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success',           true,
    'pool_request_id',   p_request_id,
    'headcount_created', v_req.headcount_needed,
    'vcodes',            ARRAY[v_vcode],
    'vacancy_ids',       ARRAY[v_vacancy_id]
  );
END;
$function$;

-- 5. repair_pool_request_slot
CREATE OR REPLACE FUNCTION public.repair_pool_request_slot(p_request_id uuid, p_operational_account_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role_level          int;
  v_caller_id           uuid;
  v_req                 public.workforce_pool_requests%ROWTYPE;
  v_item_count          int;
  v_pool_type_code      text;
  v_moses_hq_id         uuid;
  v_vcode               text;
  v_vacancy_id          uuid;
  v_vacancy             public.vacancies%ROWTYPE;
  v_op_account_id       uuid;
  v_op_account_name     text;
  v_op_group_id         uuid;
  v_op_group_name       text;
  v_slots_updated       int;
  i                     int;
BEGIN
  v_role_level := public.get_my_role_level();
  IF v_role_level IS NULL OR v_role_level NOT IN (100, 90, 30) THEN
    RAISE EXCEPTION 'Unauthorized: repair_pool_request_slot requires Data Team/Admin access';
  END IF;

  v_caller_id := auth.uid();

  SELECT * INTO v_req
  FROM public.workforce_pool_requests
  WHERE id = p_request_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pool request not found: %', p_request_id;
  END IF;
  IF v_req.status <> 'approved' THEN
    RAISE EXCEPTION 'repair_pool_request_slot only repairs approved requests (status = %)', v_req.status;
  END IF;

  -- Hard guard for position_id validity
  IF NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = v_req.position_id
  ) THEN
    RAISE EXCEPTION 'Invalid position_id: %', v_req.position_id;
  END IF;

  SELECT COUNT(*) INTO v_item_count
  FROM public.workforce_pool_request_items
  WHERE request_id = p_request_id;

  SELECT id INTO v_moses_hq_id
  FROM public.accounts
  WHERE is_pool_account = true AND is_active = true
  LIMIT 1;

  -- ── Case B: items exist AND caller supplied an operational account ─────────
  IF v_item_count > 0 AND p_operational_account_id IS NOT NULL THEN
    SELECT v.* INTO v_vacancy
    FROM public.vacancies v
    JOIN public.workforce_pool_request_items wpri ON wpri.vacancy_id = v.id
    WHERE wpri.request_id = p_request_id
    LIMIT 1;

    IF v_vacancy.id IS NULL THEN
      RAISE EXCEPTION 'BUG: items exist but no linked vacancy found for request %', p_request_id;
    END IF;

    IF COALESCE(v_vacancy.account_id = v_moses_hq_id, false) = false THEN
      RETURN jsonb_build_object(
        'success',          true,
        'already_repaired', true,
        'vacancy_id',       v_vacancy.id,
        'vacancy_account',  v_vacancy.account,
        'message',          'Vacancy is already under a non-pool account — no repair needed.'
      );
    END IF;

    SELECT a.account_name, a.group_id, g.group_name
    INTO   v_op_account_name, v_op_group_id, v_op_group_name
    FROM   public.accounts a
    LEFT   JOIN public.groups g ON g.id = a.group_id
    WHERE  a.id = p_operational_account_id AND a.is_active = true
      AND  COALESCE(a.is_pool_account, false) = false;
    IF v_op_account_name IS NULL THEN
      RAISE EXCEPTION 'Operational account not found, inactive, or is the pool account: %', p_operational_account_id;
    END IF;

    UPDATE public.vacancies
    SET account    = v_op_account_name,
        account_id = p_operational_account_id,
        group_id   = v_op_group_id,
        updated_at = now()
    WHERE id = v_vacancy.id;

    UPDATE public.workforce_pool_slots
    SET account    = v_op_account_name,
        account_id = p_operational_account_id,
        group_id   = v_op_group_id,
        updated_at = now(),
        updated_by = v_caller_id::text
    WHERE vacancy_id = v_vacancy.id
      AND deleted_at IS NULL;
    GET DIAGNOSTICS v_slots_updated = ROW_COUNT;

    UPDATE public.workforce_pool_requests
    SET
      operational_account_id   = p_operational_account_id,
      operational_account_name = v_op_account_name,
      operational_group_id     = v_op_group_id,
      operational_group_name   = v_op_group_name,
      updated_by               = v_caller_id::text,
      updated_at               = now()
    WHERE id = p_request_id;

    RETURN jsonb_build_object(
      'success',          true,
      'repaired',         true,
      'repair_type',      'account_corrected',
      'vacancy_id',       v_vacancy.id,
      'vcode',            v_vacancy.vcode,
      'new_account',      v_op_account_name,
      'new_account_id',   p_operational_account_id,
      'slots_updated',    v_slots_updated,
      'message',          'Vacancy and slots moved from Moses HQ to operational account.'
    );
  END IF;

  -- ── Case A: no items → guard intact → return already_intact ───────────────
  IF v_item_count > 0 AND p_operational_account_id IS NULL THEN
    SELECT vacancy_id INTO v_vacancy_id
    FROM public.workforce_pool_request_items
    WHERE request_id = p_request_id LIMIT 1;
    RETURN jsonb_build_object(
      'success',        true,
      'already_intact', true,
      'item_count',     v_item_count,
      'vacancy_id',     v_vacancy_id,
      'message',        'Request already has vacancy items. Pass p_operational_account_id to correct account ownership.'
    );
  END IF;

  -- ── Case A: items = 0 → create vacancy + slots + item ─────────────────────
  SELECT code INTO v_pool_type_code
  FROM public.workforce_pool_types
  WHERE id = v_req.pool_type_id;

  v_op_account_id := COALESCE(p_operational_account_id, v_req.requesting_account_id);
  SELECT a.account_name, a.group_id, g.group_name
  INTO   v_op_account_name, v_op_group_id, v_op_group_name
  FROM   public.accounts a
  LEFT   JOIN public.groups g ON g.id = a.group_id
  WHERE  a.id = v_op_account_id AND a.is_active = true;

  v_vcode := public.generate_pool_vcode(v_pool_type_code);

  INSERT INTO public.vacancies (
    vcode, account, account_id, group_id,
    position, position_id, store_id,
    status, vacant_date, required_headcount, source,
    is_pool_vacancy, pool_type_id, home_account_id,
    affects_required_hc, affects_mfr, pool_request_id,
    created_by, is_ops_request,
    province, area_city
  )
  SELECT
    v_vcode,
    v_op_account_name, v_op_account_id, v_op_group_id,
    p.position_name, p.id, v_req.requesting_store_id,
    'Open', now(), v_req.headcount_needed, 'pool',
    true, v_req.pool_type_id, v_moses_hq_id,
    false, false, v_req.id,
    COALESCE(v_req.created_by::uuid, v_caller_id), true,
    v_req.requested_province, v_req.requested_city
  FROM public.positions p
  WHERE p.id = v_req.position_id
  RETURNING id INTO v_vacancy_id;

  FOR i IN 1..v_req.headcount_needed LOOP
    INSERT INTO public.workforce_pool_slots (
      vcode, pool_type_id, vacancy_id,
      status, account, account_id, group_id, created_by
    ) VALUES (
      v_vcode, v_req.pool_type_id, v_vacancy_id,
      'open', v_op_account_name, v_op_account_id,
      v_op_group_id, COALESCE(v_req.created_by::uuid, v_caller_id)
    );
  END LOOP;

  INSERT INTO public.workforce_pool_request_items (
    request_id, vacancy_id, vcode, position_id, status
  ) VALUES (
    v_req.id, v_vacancy_id, v_vcode, v_req.position_id, 'open'
  );

  UPDATE public.workforce_pool_requests
  SET
    operational_account_id   = COALESCE(operational_account_id,
                                 CASE WHEN is_ops_request THEN v_op_account_id ELSE NULL END),
    operational_account_name = COALESCE(operational_account_name,
                                 CASE WHEN is_ops_request THEN v_op_account_name ELSE NULL END),
    operational_group_id     = COALESCE(operational_group_id,
                                 CASE WHEN is_ops_request THEN v_op_group_id ELSE NULL END),
    operational_group_name   = COALESCE(operational_group_name,
                                 CASE WHEN is_ops_request THEN v_op_group_name ELSE NULL END),
    updated_by               = v_caller_id::text,
    updated_at               = now()
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success',       true,
    'repaired',      true,
    'repair_type',   'items_created',
    'vcode',         v_vcode,
    'vacancy_id',    v_vacancy_id,
    'account',       v_op_account_name,
    'slots_created', v_req.headcount_needed,
    'message',       'Vacancy, slots, and item created for approved request.'
  );
END;
$function$;

-- 6. create_vacancy_request
CREATE OR REPLACE FUNCTION public.create_vacancy_request(p_account_id uuid, p_store_id uuid, p_position_id uuid, p_vacancy_type text DEFAULT 'New'::text, p_required_headcount integer DEFAULT 1, p_vacant_date date DEFAULT NULL::date, p_remarks text DEFAULT NULL::text, p_source_plantilla_id uuid DEFAULT NULL::uuid, p_has_penalty boolean DEFAULT false, p_penalty_amount numeric DEFAULT NULL::numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id uuid := public.get_my_profile_id();
  v_role       text := public.get_my_role();
  v_role_lvl   int  := public.get_my_role_level();
  v_account    record;
  v_store      record;
  v_position   record;
  v_new_id     uuid;
  v_dup_id     uuid;
  v_plant      record;
BEGIN
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;

  IF v_role_lvl < 30 OR v_role IN ('Viewer','Back Office') THEN
    RAISE EXCEPTION 'Role % cannot create vacancies', v_role USING ERRCODE = '42501';
  END IF;

  IF NOT public.i_have_account_scope(p_account_id) THEN
    RAISE EXCEPTION 'Account % is outside your scope', p_account_id USING ERRCODE = '42501';
  END IF;

  -- Hard guard for position_id validity
  IF NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = p_position_id
  ) THEN
    RAISE EXCEPTION 'Invalid position_id: %', p_position_id;
  END IF;

  SELECT a.* INTO v_account FROM public.accounts a WHERE a.id = p_account_id;
  IF NOT FOUND OR v_account.is_active IS NOT TRUE THEN
    RAISE EXCEPTION 'Account not found or inactive: %', p_account_id;
  END IF;

  SELECT s.* INTO v_store FROM public.stores s WHERE s.id = p_store_id;
  IF NOT FOUND OR COALESCE(v_store.is_active, true) = false THEN
    RAISE EXCEPTION 'Store not found or inactive: %', p_store_id;
  END IF;
  IF v_store.account_id IS NOT NULL AND v_store.account_id <> p_account_id THEN
    RAISE EXCEPTION 'Store % does not belong to account %', p_store_id, p_account_id;
  END IF;

  SELECT pos.* INTO v_position FROM public.positions pos WHERE pos.id = p_position_id;
  IF NOT FOUND OR COALESCE(v_position.is_active, true) = false THEN
    RAISE EXCEPTION 'Position not found or inactive: %', p_position_id;
  END IF;

  IF p_source_plantilla_id IS NOT NULL THEN
    SELECT pl.* INTO v_plant FROM public.plantilla pl WHERE pl.id = p_source_plantilla_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Source plantilla not found: %', p_source_plantilla_id;
    END IF;
    IF v_plant.account_id IS NOT NULL AND v_plant.account_id <> p_account_id THEN
      RAISE EXCEPTION 'Source plantilla account mismatch';
    END IF;
    IF v_plant.store_id IS NOT NULL AND v_plant.store_id <> p_store_id THEN
      RAISE EXCEPTION 'Source plantilla store mismatch';
    END IF;
    IF v_plant.position_id IS NOT NULL AND v_plant.position_id <> p_position_id THEN
      RAISE EXCEPTION 'Source plantilla position mismatch';
    END IF;
  END IF;

  SELECT v.id INTO v_dup_id
  FROM public.vacancies v
  WHERE v.store_id = p_store_id
    AND v.position_id = p_position_id
    AND v.status IN ('Draft','Pending Approval','Open','On Hold')
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
  LIMIT 1;

  IF v_dup_id IS NOT NULL THEN
    RAISE EXCEPTION 'Duplicate active vacancy already exists for this store/position (id=%)', v_dup_id
      USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO public.vacancies (
    account_id, store_id, position_id,
    account, store_name, position,
    vacancy_type, required_headcount, vacant_date,
    remarks, source_plantilla_id,
    has_penalty, penalty_amount,
    status, requested_by_user_id, created_by, created_by_user_id, requested_date
  )
  SELECT
    p_account_id, p_store_id, p.id,
    v_account.account_name, v_store.store_name, p.position_name,
    COALESCE(p_vacancy_type,'New'), GREATEST(p_required_headcount,1), p_vacant_date,
    p_remarks, p_source_plantilla_id,
    COALESCE(p_has_penalty,false), p_penalty_amount,
    'Draft', v_profile_id, v_profile_id, v_profile_id, CURRENT_DATE
  FROM public.positions p
  WHERE p.id = p_position_id
  RETURNING id INTO v_new_id;

  PERFORM public.log_audit_event(
    'vacancies', 'INSERT', v_new_id, NULL,
    jsonb_build_object('semantic_action','CREATE_VACANCY_REQUEST',
                       'actor_role', v_role,
                       'account_id', p_account_id,
                       'store_id',   p_store_id,
                       'position_id', p_position_id)
  );
  RETURN v_new_id;
END;
$function$;

-- 7. _execute_approved_coverage_request
CREATE OR REPLACE FUNCTION public._execute_approved_coverage_request(p_request coverage_requests, p_actor_id uuid, p_actor_name text, p_actor_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  -- ── iteration / loop cursors
  v_store_id               uuid;
  v_pl                     record;

  -- ── remove_store semantics (corrected per ohm#25f6a6ra)
  v_removed_store_ids      uuid[];
  v_remaining_store_ids    uuid[];
  v_remaining_count        integer;

  -- ── add_store
  v_store_ids              uuid[];
  v_replacement_store_ids  uuid[];

  v_below_minimum_action   text;

  -- ── reporting
  v_existing_cg_code       text;
  v_anchor_removed         boolean := false;
  v_stores_added           integer := 0;
  v_stores_removed         integer := 0;
  v_group_archived         boolean := false;
  v_notes                  text[]  := ARRAY[]::text[];

  -- ── stationary-conversion helpers
  v_remaining_store_id     uuid;
  v_remaining_store_name   text;
  v_remaining_store_vcode  text;

  -- ── imported-employee helpers
  v_active_allocs          integer;

  -- ── vacancy / slot reopening helpers
  v_existing_slot_id       uuid;
  v_new_slot_id            uuid;
  v_rows_updated           integer;
  v_store_account_id       uuid;
  v_store_group_id         uuid;
  v_store_vcode            text;
  v_store_name_local       text;
  v_store_account_name     text;
  v_store_position         text;
  v_store_employment_type  text;
  v_store_position_id      uuid;
  v_store_province_id      uuid;   -- always NULL; stores has no province_id
  v_store_area             text;
  v_store_chain_id         uuid;

  -- ── Bug 1 fix: pre-resolved group_id fallback from CG account
  v_cg_account_group_id    uuid;

  -- ── Bug 2 fix: pre-resolved position from coverage_groups → positions
  v_cg_position_name       text;
  v_cg_position_id         uuid;

  -- ── GAP-02 dissolve variables
  v_employee_home_stores   jsonb;
  v_retained_store_ids     uuid[];
  v_dissolved_store_ids    uuid[];
  v_employees_converted    integer := 0;
  v_vacancies_reopened     integer := 0;

  -- ── create_coverage_group variables
  v_new_cg_id              uuid;
  v_cg_code                text;
  v_store_count            integer;
  v_slot_ordinal           integer := 0;
  v_slot_id                uuid;
  v_anchor_store_name      text;
  v_anchor_store_vcode     text;
  v_old_slot_id            uuid;
  v_old_vcode              text;

  -- ── ohm#4h8w1qz6: anchor position inheritance
  v_anchor_store_id        uuid;
  v_resolved_position_id   uuid;

  -- ── ohm#8a4f71d2 merge_coverage_groups variables
  v_surviving_cg_id        uuid;
  v_merged_cg_id           uuid;
  v_surviving_cg_code      text;
  v_merged_cg_code         text;
  v_stores_transferred     integer := 0;
  v_employees_transferred  integer := 0;
BEGIN

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── create_coverage_group ───────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  IF p_request.request_type = 'create_coverage_group'::public.request_type THEN
    v_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);
    v_store_count := COALESCE(array_length(v_store_ids, 1), 0);

    IF v_store_count < 2 THEN
      RAISE EXCEPTION 'Coverage Group must have at least 2 member stores.' USING ERRCODE = '23514';
    END IF;

    v_new_cg_id := gen_random_uuid();
    v_cg_code := public.fn_generate_cgcode_for_account(p_request.account_id);

    -- ── ohm#4h8w1qz6 Fix 2 (corrected 20260706000013): resolve position_id from
    -- anchor store BEFORE insert. plantilla_slots has NO position_id column — only
    -- text `position`. Prefer the anchor's active plantilla occupant's
    -- plantilla.position_id; fall back to matching plantilla_slots.position
    -- (text) against positions.position_name for an open slot. NULL if neither.
    v_anchor_store_id := (p_request.payload ->> 'anchor_store_id')::uuid;

    SELECT pl2.position_id INTO v_resolved_position_id
    FROM public.plantilla pl2
    WHERE pl2.store_id = v_anchor_store_id
      AND pl2.account_id = p_request.account_id
      AND pl2.status = 'Active'
      AND COALESCE(pl2.is_deleted, false) = false
      AND COALESCE(pl2.is_archived, false) = false
      AND pl2.position_id IS NOT NULL
    ORDER BY pl2.updated_at DESC
    LIMIT 1;

    IF v_resolved_position_id IS NULL THEN
      SELECT pos.id INTO v_resolved_position_id
      FROM public.plantilla_slots ps
      JOIN public.positions pos ON pos.position_name = ps.position
      WHERE ps.store_id = v_anchor_store_id
        AND ps.account_id = p_request.account_id
        AND ps.slot_status = 'open'
      ORDER BY ps.created_at DESC
      LIMIT 1;
    END IF;

    -- STEP 1: Create coverage group structure
    INSERT INTO public.coverage_groups (
      id, coverage_code, account_id, position_id,
      employment_type, required_headcount, status,
      area_name, created_by, created_at
    ) VALUES (
      v_new_cg_id, v_cg_code, p_request.account_id, v_resolved_position_id,
      p_request.employment_type, v_store_count, 'open',
      p_request.payload ->> 'area_name', p_actor_id, now()
    );

    SELECT store_name, vcode INTO v_anchor_store_name, v_anchor_store_vcode
    FROM public.stores
    WHERE id = (p_request.payload ->> 'anchor_store_id')::uuid;

    -- STEP 2: Create coverage group member edges
    FOREACH v_store_id IN ARRAY v_store_ids LOOP
      INSERT INTO public.coverage_group_stores (
        coverage_group_id, store_id, is_anchor, added_by
      ) VALUES (
        v_new_cg_id, v_store_id, (v_store_id = (p_request.payload ->> 'anchor_store_id')::uuid), p_actor_id
      );
    END LOOP;

    -- STEP 3 & 4: Evaluate member stores and assign active employees
    v_slot_ordinal := 0;
    FOR v_pl IN (
      SELECT pl.*, a.group_id
      FROM public.plantilla pl
      JOIN public.accounts a ON a.id = pl.account_id
      WHERE pl.store_id = ANY(v_store_ids)
        AND pl.account_id = p_request.account_id
        AND (p_request.position_id IS NULL OR pl.position_id = p_request.position_id)
        AND pl.status = 'Active'
        AND COALESCE(pl.is_deleted, false) = false
        AND COALESCE(pl.is_archived, false) = false
    ) LOOP
      v_slot_id := gen_random_uuid();
      v_slot_ordinal := v_slot_ordinal + 1;

      -- Create active coverage slot row
      INSERT INTO public.coverage_slots (
        id, coverage_group_id, slot_ordinal, slot_status, current_occupant_plantilla_id, created_at, updated_at
      ) VALUES (
        v_slot_id, v_new_cg_id, v_slot_ordinal, 'active', v_pl.id, now(), now()
      );

      -- Update employee plantilla row to roving
      UPDATE public.plantilla
      SET deployment_type = 'Roving',
          coverage_group_id = v_new_cg_id,
          coverage_slot_id = v_slot_id,
          store_id = (p_request.payload ->> 'anchor_store_id')::uuid,
          store_name = v_anchor_store_name,
          vcode = NULL
      WHERE id = v_pl.id;

      -- Vacate/open old stationary slot in plantilla_slots
      SELECT id, legacy_vcode INTO v_old_slot_id, v_old_vcode
      FROM public.plantilla_slots
      WHERE current_occupant_plantilla_id = v_pl.id
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_old_slot_id IS NOT NULL THEN
        UPDATE public.plantilla_slots
        SET slot_status = 'open',
            current_occupant_plantilla_id = NULL,
            updated_at = now(),
            updated_by = p_actor_id
        WHERE id = v_old_slot_id;

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type,
          old_value, new_value, reason_code,
          performed_by, remarks, created_at
        ) VALUES (
          v_old_slot_id, v_pl.account_id, 'employee_separated',
          'occupied', 'open', 'COVERAGE_GROUP_CREATED',
          p_actor_id, 'Employee converted to roving coverage in group ' || v_cg_code || '.', now()
        );
      END IF;

      -- Reconcile assignments/allocations
      IF v_pl.source_employee_import_batch_id IS NOT NULL
         OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        -- Deactivate old allocations
        UPDATE public.employee_store_allocations
        SET is_active = false,
            effective_end = CURRENT_DATE
        WHERE plantilla_id = v_pl.id AND is_active = true;

        -- Insert new allocations for all group stores
        FOREACH v_store_id IN ARRAY v_store_ids LOOP
          SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
          FROM public.stores WHERE id = v_store_id;

          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          ) VALUES (
            v_pl.id, v_pl.employee_no, v_new_cg_id,
            v_store_id, v_store_vcode, v_store_name_local,
            v_pl.account_id, v_pl.group_id,
            round(1.0 / v_store_count, 4), v_store_count,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, p_actor_id
          );
        END LOOP;
      ELSE
        -- Live employee: deactivate old store links
        UPDATE public.plantilla_store_links
        SET status = 'Resigned',
            deleted_at = now(),
            unlinked_at = now(),
            unlinked_by = p_actor_id
        WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;

        -- Insert new store links for all group stores
        FOREACH v_store_id IN ARRAY v_store_ids LOOP
          SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
          FROM public.stores WHERE id = v_store_id;

          INSERT INTO public.plantilla_store_links (
            plantilla_id,
            coverage_group_id,
            vcode,
            store_name,
            account,
            status,
            linked_at,
            linked_by,
            created_by,
            updated_by
          ) VALUES (
            v_pl.id,
            v_new_cg_id,
            v_store_vcode,
            v_store_name_local,
            (SELECT account_name FROM public.accounts WHERE id = v_pl.account_id),
            'Active',
            now(),
            p_actor_id,
            p_actor_id,
            p_actor_id
          );
        END LOOP;

        PERFORM public.fn_sync_employee_store_allocations(v_pl.employee_no);
      END IF;

      v_employees_converted := v_employees_converted + 1;
      v_notes := v_notes || ARRAY[
        'employee:' || COALESCE(v_pl.employee_name, v_pl.employee_no, v_pl.id::text)
        || '|assigned_to_coverage_group:' || v_cg_code
      ];
    END LOOP;

    -- ── ohm#4h8w1qz6 Fix 1: exactly 1 open coverage_slots row for pure-structure
    IF v_employees_converted = 0 THEN
      INSERT INTO public.coverage_slots (
        coverage_group_id, slot_ordinal, slot_status, current_occupant_plantilla_id, created_at, updated_at
      ) VALUES (
        v_new_cg_id, 1, 'open', NULL, now(), now()
      );
    END IF;

    -- Link request target_coverage_group_id to the new group
    UPDATE public.coverage_requests
    SET target_coverage_group_id = v_new_cg_id
    WHERE id = p_request.id;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 'create_coverage_group',
      'coverage_group_id',            v_new_cg_id,
      'coverage_code',                v_cg_code,
      'stores_added',                 v_store_count,
      'employees_converted',          v_employees_converted,
      'notes',                        to_jsonb(v_notes)
    );

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── add_store ───────────────────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'add_store'::public.request_type THEN
    v_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);

    FOREACH v_store_id IN ARRAY v_store_ids LOOP
      SELECT cg.coverage_code INTO v_existing_cg_code
      FROM public.coverage_group_stores cgs
      JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
      WHERE cgs.store_id = v_store_id
        AND cgs.archived_at IS NULL
        AND cg.archived_at IS NULL
        AND cg.id <> p_request.target_coverage_group_id
      LIMIT 1;

      IF v_existing_cg_code IS NOT NULL THEN
        RAISE EXCEPTION
          'store % is already active in coverage group %; remove it first',
          v_store_id, v_existing_cg_code
          USING ERRCODE = '23514';
      END IF;

      IF EXISTS (
        SELECT 1 FROM public.coverage_group_stores
        WHERE coverage_group_id = p_request.target_coverage_group_id
          AND store_id = v_store_id
          AND archived_at IS NULL
      ) THEN
        RAISE EXCEPTION
          'store % is already an active member of this coverage group',
          v_store_id
          USING ERRCODE = '23514';
      END IF;

      INSERT INTO public.coverage_group_stores (
        coverage_group_id, store_id, is_anchor, added_by
      ) VALUES (
        p_request.target_coverage_group_id, v_store_id, false, p_actor_id
      );
      v_stores_added := v_stores_added + 1;

      FOR v_pl IN (
        SELECT pl.*, a.group_id
        FROM public.plantilla pl
        JOIN public.accounts a ON a.id = pl.account_id
        WHERE pl.coverage_group_id = p_request.target_coverage_group_id
          AND pl.status = 'Active'
          AND pl.is_deleted = false
          AND pl.is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          IF NOT EXISTS (
            SELECT 1 FROM public.employee_store_allocations
            WHERE plantilla_id = v_pl.id AND store_id = v_store_id AND is_active = true
          ) THEN
            SELECT store_name, vcode
            INTO v_remaining_store_name, v_remaining_store_vcode
            FROM public.stores WHERE id = v_store_id;

            INSERT INTO public.employee_store_allocations (
              plantilla_id, employee_no, roving_group_id,
              store_id, vcode, store_name,
              account_id, group_id,
              filled_hc, active_store_count,
              effective_start, is_active,
              source_import_batch_id, created_by
            ) VALUES (
              v_pl.id, v_pl.employee_no, p_request.target_coverage_group_id,
              v_store_id, v_remaining_store_vcode, v_remaining_store_name,
              v_pl.account_id, v_pl.group_id,
              1, 1,
              CURRENT_DATE, true,
              v_pl.source_baseline_import_batch_id, p_actor_id
            );
          END IF;
        END IF;
      END LOOP;
    END LOOP;

    FOR v_pl IN (
      SELECT * FROM public.plantilla
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND status = 'Active'
        AND is_deleted = false
        AND is_archived = false
    ) LOOP
      IF v_pl.source_employee_import_batch_id IS NOT NULL
        OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        SELECT COUNT(*) INTO v_active_allocs
        FROM public.employee_store_allocations
        WHERE plantilla_id = v_pl.id AND is_active = true;

        IF v_active_allocs > 0 THEN
          UPDATE public.employee_store_allocations
          SET active_store_count = v_active_allocs,
              filled_hc = round(1.0 / v_active_allocs, 4)
          WHERE plantilla_id = v_pl.id AND is_active = true;
        END IF;
      END IF;
    END LOOP;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 'add_store',
      'stores_added',                 v_stores_added,
      'stores_removed',               0,
      'group_archived',               false,
      'below_minimum_action_applied', null,
      'notes',                        to_jsonb(v_notes)
    );


  -- ════════════════════════════════════════════════════════════════════════════
  -- ── remove_store / convert_roving_to_stationary ─────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'remove_store'::public.request_type
     OR p_request.request_type = 'convert_roving_to_stationary'::public.request_type
  THEN

    -- Pre-resolve group_id from coverage group's account
    SELECT a.group_id
    INTO v_cg_account_group_id
    FROM public.coverage_groups cg
    JOIN public.accounts a ON a.id = cg.account_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- Pre-resolve position from coverage_groups → positions
    SELECT pos.position_name, cg.position_id
    INTO v_cg_position_name, v_cg_position_id
    FROM public.coverage_groups cg
    LEFT JOIN public.positions pos ON pos.id = cg.position_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- Resolve which stores are being REMOVED
    IF p_request.request_type = 'convert_roving_to_stationary'::public.request_type THEN
      v_remaining_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);
      SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_removed_store_ids
      FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND archived_at IS NULL
        AND NOT (store_id = ANY (v_remaining_store_ids));
      v_remaining_count := COALESCE(array_length(v_remaining_store_ids, 1), 0);
      v_below_minimum_action := 'convert_remaining_to_standalone';
    ELSE
      v_removed_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);

      IF EXISTS (
        SELECT 1 FROM unnest(v_removed_store_ids) AS rid
        WHERE NOT EXISTS (
          SELECT 1 FROM public.coverage_group_stores
          WHERE coverage_group_id = p_request.target_coverage_group_id
            AND store_id = rid
            AND archived_at IS NULL
        )
      ) THEN
        RAISE EXCEPTION
          'remove_store: one or more store_ids are not active members of this coverage group'
          USING ERRCODE = '23514';
      END IF;

      SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_remaining_store_ids
      FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND archived_at IS NULL
        AND NOT (store_id = ANY (v_removed_store_ids));

      v_remaining_count := COALESCE(array_length(v_remaining_store_ids, 1), 0);

      IF v_remaining_count = 0 THEN
        RAISE EXCEPTION
          'remove_store would leave 0 active stores; use dissolve_coverage_group instead'
          USING ERRCODE = '23514';
      ELSIF v_remaining_count = 1 THEN
        v_below_minimum_action := 'convert_remaining_to_standalone';
      ELSE
        v_below_minimum_action := NULL;
      END IF;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = ANY (v_removed_store_ids)
        AND is_anchor = true
        AND archived_at IS NULL
    ) THEN
      v_anchor_removed := true;
      v_notes := v_notes || ARRAY['anchor store removed; group has no active anchor'];
    END IF;

    -- Employee Integrity Lock
    IF v_remaining_count >= 2 THEN
      FOR v_pl IN (
        SELECT pl.*, a.group_id
        FROM public.plantilla pl
        JOIN public.accounts a ON a.id = pl.account_id
        WHERE pl.coverage_group_id = p_request.target_coverage_group_id
          AND pl.status = 'Active'
          AND pl.is_deleted = false
          AND pl.is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          -- Imported employee: count ESA rows that survive after removal
          SELECT COUNT(*) INTO v_active_allocs
          FROM public.employee_store_allocations
          WHERE plantilla_id = v_pl.id
            AND is_active = true
            AND NOT (store_id = ANY(v_removed_store_ids));

          IF v_active_allocs = 0 THEN
            RAISE EXCEPTION
              'Employee integrity lock: removing these stores would leave employee % (%) with 0 active store assignments. '
              'Retain at least one store for this employee, or use Dissolve Coverage Group.',
              COALESCE(v_pl.employee_name, ''), COALESCE(v_pl.employee_no, '')
              USING ERRCODE = '23514';
          END IF;
        ELSE
          -- Non-imported employee: count active store links surviving after removal
          SELECT COUNT(*) INTO v_active_allocs
          FROM public.plantilla_store_links psl
          JOIN public.stores s ON psl.vcode = s.vcode
          WHERE psl.plantilla_id = v_pl.id
            AND psl.deleted_at IS NULL
            AND NOT (s.id = ANY(v_removed_store_ids));

          IF v_active_allocs = 0 THEN
            RAISE EXCEPTION
              'Employee integrity lock: removing these stores would leave employee % (%) with 0 active store assignments. '
              'Retain at least one store for this employee, or use Dissolve Coverage Group.',
              COALESCE(v_pl.employee_name, ''), COALESCE(v_pl.employee_no, '')
              USING ERRCODE = '23514';
          END IF;
        END IF;
      END LOOP;
    END IF;

    -- Branch A: convert_remaining_to_standalone (remaining_count = 1)
    IF v_below_minimum_action = 'convert_remaining_to_standalone' THEN
      v_remaining_store_id := v_remaining_store_ids[1];
      SELECT store_name, vcode
      INTO v_remaining_store_name, v_remaining_store_vcode
      FROM public.stores WHERE id = v_remaining_store_id;

      FOR v_pl IN (
        SELECT pl.*, a.group_id
        FROM public.plantilla pl
        JOIN public.accounts a ON a.id = pl.account_id
        WHERE pl.coverage_group_id = p_request.target_coverage_group_id
          AND pl.status = 'Active'
          AND pl.is_deleted = false
          AND pl.is_archived = false
      ) LOOP
        UPDATE public.plantilla
        SET deployment_type   = 'Stationary',
            coverage_group_id = NULL,
            coverage_slot_id  = NULL,
            store_id          = v_remaining_store_id,
            store_name        = v_remaining_store_name,
            vcode             = v_remaining_store_vcode
        WHERE id = v_pl.id;

        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          UPDATE public.employee_store_allocations
          SET is_active = false, effective_end = CURRENT_DATE
          WHERE plantilla_id = v_pl.id AND is_active = true;

          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          ) VALUES (
            v_pl.id, v_pl.employee_no, NULL,
            v_remaining_store_id, v_remaining_store_vcode, v_remaining_store_name,
            v_pl.account_id, v_pl.group_id,
            1.0, 1,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, p_actor_id
          );
        ELSE
          UPDATE public.plantilla_store_links
          SET status = 'Resigned', deleted_at = now()
          WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;
        END IF;
      END LOOP;

      UPDATE public.coverage_group_stores
      SET archived_at = now(), archived_by = p_actor_id
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = v_remaining_store_id
        AND archived_at IS NULL;

      UPDATE public.coverage_slots
      SET slot_status = 'closed', updated_at = now()
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND slot_status <> 'closed';

      UPDATE public.coverage_groups
      SET archived_at    = now(),
          archived_by    = p_actor_id,
          archive_reason = 'Coverage Request execution: converted remaining store to standalone'
      WHERE id = p_request.target_coverage_group_id;

      v_group_archived := true;
      v_notes := v_notes || ARRAY['remaining store converted to standalone; group archived'];
    END IF;

    -- Archive removed store edges + employee sync
    IF NOT v_group_archived THEN
      UPDATE public.coverage_group_stores
      SET archived_at = now(), archived_by = p_actor_id
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = ANY (v_removed_store_ids)
        AND archived_at IS NULL;

      GET DIAGNOSTICS v_stores_removed = ROW_COUNT;

      FOR v_pl IN (
        SELECT * FROM public.plantilla
        WHERE coverage_group_id = p_request.target_coverage_group_id
          AND status = 'Active'
          AND is_deleted = false
          AND is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          UPDATE public.employee_store_allocations
          SET is_active = false, effective_end = CURRENT_DATE
          WHERE plantilla_id = v_pl.id
            AND store_id = ANY (v_removed_store_ids)
            AND is_active = true;

          SELECT COUNT(*) INTO v_active_allocs
          FROM public.employee_store_allocations
          WHERE plantilla_id = v_pl.id AND is_active = true;

          IF v_active_allocs > 0 THEN
            UPDATE public.employee_store_allocations
            SET active_store_count = v_active_allocs,
                filled_hc = round(1.0 / v_active_allocs, 4)
            WHERE plantilla_id = v_pl.id AND is_active = true;
          END IF;
        ELSE
          UPDATE public.plantilla_store_links psl
          SET status = 'Resigned', deleted_at = now(), unlinked_at = now(), unlinked_by = p_actor_id
          FROM public.stores s
          WHERE psl.vcode = s.vcode
            AND psl.plantilla_id = v_pl.id
            AND s.id = ANY(v_removed_store_ids)
            AND psl.deleted_at IS NULL;
        END IF;
      END LOOP;
    END IF;

    -- Vacancy Slot Reopening for each removed store
    FOREACH v_store_id IN ARRAY v_removed_store_ids LOOP
      SELECT
        s.store_name,
        s.vcode,
        s.account_id,
        s.group_id,
        a.account_name,
        COALESCE(s.area_city, s.area_province, '') AS area_name
      INTO
        v_store_name_local,
        v_store_vcode,
        v_store_account_id,
        v_store_group_id,
        v_store_account_name,
        v_store_area
      FROM public.stores s
      LEFT JOIN public.accounts a ON a.id = s.account_id
      WHERE s.id = v_store_id;

      v_store_group_id := COALESCE(v_store_group_id, v_cg_account_group_id);
      v_store_province_id := NULL;

      IF v_store_vcode IS NULL THEN
        v_notes := v_notes || ARRAY['store ' || v_store_id::text || ' has no vcode; vacancy not created'];
        CONTINUE;
      END IF;

      SELECT
        COALESCE(pl.position, 'Unknown'),
        pl.position_id,
        pl.chain_id
      INTO
        v_store_position,
        v_store_position_id,
        v_store_chain_id
      FROM public.plantilla pl
      WHERE pl.coverage_group_id = p_request.target_coverage_group_id
        AND pl.is_deleted = false
        AND pl.is_archived = false
      LIMIT 1;

      IF v_store_position IS NULL OR v_store_position = 'Unknown' THEN
        v_store_position    := COALESCE(v_cg_position_name, 'Unknown');
        v_store_position_id := COALESCE(v_store_position_id, v_cg_position_id);
      END IF;

      -- Hard guard for position_id validity
      IF NOT EXISTS (
        SELECT 1 FROM public.positions WHERE id = v_store_position_id
      ) THEN
        RAISE EXCEPTION 'Invalid position_id: %', v_store_position_id;
      END IF;

      v_store_employment_type := 'Stationary';

      UPDATE public.vacancies
      SET status              = 'Open',
          is_archived         = false,
          archived_at         = NULL,
          has_pending_closure = false,
          vacant_date         = CURRENT_DATE,
          updated_at          = now()
      WHERE vcode      = v_store_vcode
        AND deleted_at IS NULL
        AND status NOT IN ('Open', 'Pipeline');

      GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

      IF v_rows_updated = 0 THEN
        INSERT INTO public.vacancies (
          vcode, account, position,
          account_id, chain_id, store_id,
          province_id, area_name, position_id,
          vacant_date, vacancy_type, status,
          source_plantilla_id, store_name,
          created_at, updated_at, required_headcount
        )
        SELECT
          v_store_vcode,
          COALESCE(v_store_account_name, 'UNKNOWN'),
          p.position_name,
          v_store_account_id,
          v_store_chain_id,
          v_store_id,
          v_store_province_id,
          v_store_area,
          p.id,
          CURRENT_DATE,
          'Backfill',
          'Open',
          NULL,
          v_store_name_local,
          now(), now(), 1
        FROM public.positions p
        WHERE p.id = v_store_position_id
        ON CONFLICT DO NOTHING;
      END IF;

      SELECT id INTO v_existing_slot_id
      FROM public.plantilla_slots
      WHERE store_id   = v_store_id
        AND account_id = v_store_account_id
        AND slot_status <> 'closed'
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_existing_slot_id IS NOT NULL THEN
        UPDATE public.plantilla_slots
        SET slot_status                   = 'open',
            employment_type               = 'Stationary',
            is_roving                     = false, -- Bug Fix: reset to false when converted back to stationary
            group_id                      = COALESCE(group_id, v_store_group_id),
            current_occupant_plantilla_id  = NULL,
            closed_at                      = NULL,
            closed_by                      = NULL,
            closure_reason_code            = NULL,
            updated_at                     = now(),
            updated_by                     = p_actor_id
        WHERE id = v_existing_slot_id;

        v_new_slot_id := v_existing_slot_id;
      ELSE
        SELECT id INTO v_existing_slot_id
        FROM public.plantilla_slots
        WHERE store_id   = v_store_id
          AND account_id = v_store_account_id
          AND slot_status = 'closed'
        ORDER BY updated_at DESC
        LIMIT 1;

        IF v_existing_slot_id IS NOT NULL THEN
          UPDATE public.plantilla_slots
          SET slot_status                   = 'open',
              employment_type               = 'Stationary',
              is_roving                     = false, -- Bug Fix: reset to false when converted back to stationary
              group_id                      = COALESCE(group_id, v_store_group_id),
              current_occupant_plantilla_id  = NULL,
              closed_at                      = NULL,
              closed_by                      = NULL,
              closure_reason_code            = NULL,
              legacy_vcode                   = COALESCE(legacy_vcode, v_store_vcode),
              updated_at                     = now(),
              updated_by                     = p_actor_id
          WHERE id = v_existing_slot_id;

          v_new_slot_id := v_existing_slot_id;
        ELSE
          v_new_slot_id := gen_random_uuid();
          INSERT INTO public.plantilla_slots (
            id, store_id, account_id, group_id,
            position, employment_type, is_roving,
            slot_status, legacy_vcode,
            created_by, updated_by, created_at, updated_at
          ) VALUES (
            v_new_slot_id,
            v_store_id, v_store_account_id, v_store_group_id,
            COALESCE(v_store_position, 'Unknown'),
            'Stationary',
            false,
            'open',
            v_store_vcode,
            p_actor_id, p_actor_id, now(), now()
          );
        END IF;
      END IF;

      INSERT INTO public.slot_history (
        slot_id, account_id, action_type,
        old_value, new_value, reason_code,
        performed_by, remarks, created_at
      ) VALUES (
        v_new_slot_id,
        v_store_account_id,
        'coverage_store_removed',
        'occupied_or_closed',
        'open',
        'COVERAGE_STORE_REMOVED',
        p_actor_id,
        'Coverage Request: store removed from group. Request approved by ' || p_actor_name || '.',
        now()
      );

      v_stores_removed := v_stores_removed + 1;
      v_notes := v_notes || ARRAY[
        'store_removed:' || COALESCE(v_store_name_local, v_store_id::text)
        || '|vcode:' || v_store_vcode
        || '|account:' || COALESCE(v_store_account_name, '')
      ];
    END LOOP;

    IF NOT v_group_archived THEN
      SELECT COUNT(*) INTO v_stores_removed
      FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = ANY (v_removed_store_ids)
        AND archived_at >= now() - interval '10 seconds';
    ELSE
      v_stores_removed := array_length(v_removed_store_ids, 1);
    END IF;

    RETURN jsonb_build_object(
      'structural_execution_enabled',  true,
      'request_type',                  p_request.request_type,
      'stores_added',                  v_stores_added,
      'stores_removed',                v_stores_removed,
      'removed_store_ids',             to_jsonb(v_removed_store_ids),
      'remaining_store_ids',           to_jsonb(v_remaining_store_ids),
      'remaining_count',               v_remaining_count,
      'group_archived',                v_group_archived,
      'anchor_removed',                v_anchor_removed,
      'below_minimum_action_applied',  v_below_minimum_action,
      'notes',                         to_jsonb(v_notes)
    );


  -- ════════════════════════════════════════════════════════════════════════════
  -- ── dissolve_coverage_group ─────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'dissolve_coverage_group'::public.request_type THEN

    -- Pre-resolve group/position
    SELECT a.group_id
    INTO v_cg_account_group_id
    FROM public.coverage_groups cg
    JOIN public.accounts a ON a.id = cg.account_id
    WHERE cg.id = p_request.target_coverage_group_id;

    SELECT pos.position_name, cg.position_id
    INTO v_cg_position_name, v_cg_position_id
    FROM public.coverage_groups cg
    LEFT JOIN public.positions pos ON pos.id = cg.position_id
    WHERE cg.id = p_request.target_coverage_group_id;

    v_employee_home_stores := COALESCE(
      p_request.payload -> 'employee_home_stores',
      '{}'::jsonb
    );

    -- require home store for every active employee
    FOR v_pl IN (
      SELECT pl.*, a.group_id
      FROM public.plantilla pl
      JOIN public.accounts a ON a.id = pl.account_id
      WHERE pl.coverage_group_id = p_request.target_coverage_group_id
        AND pl.status = 'Active'
        AND pl.is_deleted = false
        AND pl.is_archived = false
    ) LOOP
      IF (v_employee_home_stores ->> v_pl.id::text) IS NULL THEN
        RAISE EXCEPTION
          'Dissolve blocked: no retained home store selected for employee % (%). '
          'Select a home store for every active employee before dissolving.',
          COALESCE(v_pl.employee_name, ''), COALESCE(v_pl.employee_no, '')
          USING ERRCODE = '23514';
      END IF;
    END LOOP;

    -- Collect the set of retained store IDs
    SELECT COALESCE(array_agg(DISTINCT val::uuid), ARRAY[]::uuid[])
    INTO v_retained_store_ids
    FROM jsonb_each_text(v_employee_home_stores) AS t(key, val);

    -- Validate retained home stores are active members
    IF v_retained_store_ids IS NOT NULL AND array_length(v_retained_store_ids, 1) > 0 THEN
      IF EXISTS (
        SELECT 1 FROM unnest(v_retained_store_ids) AS rid
        WHERE NOT EXISTS (
          SELECT 1 FROM public.coverage_group_stores
          WHERE coverage_group_id = p_request.target_coverage_group_id
            AND store_id = rid
            AND archived_at IS NULL
        )
      ) THEN
        RAISE EXCEPTION
          'Dissolve blocked: one or more retained home stores are not active members of this coverage group.'
          USING ERRCODE = '23514';
      END IF;
    END IF;

    -- Compute stores losing coverage
    SELECT COALESCE(array_agg(cgs.store_id), ARRAY[]::uuid[])
    INTO v_dissolved_store_ids
    FROM public.coverage_group_stores cgs
    WHERE cgs.coverage_group_id = p_request.target_coverage_group_id
      AND cgs.archived_at IS NULL
      AND NOT (cgs.store_id = ANY(COALESCE(v_retained_store_ids, ARRAY[]::uuid[])));

    -- Convert employee to Stationary
    FOR v_pl IN (
      SELECT pl.*, a.group_id
      FROM public.plantilla pl
      JOIN public.accounts a ON a.id = pl.account_id
      WHERE pl.coverage_group_id = p_request.target_coverage_group_id
        AND pl.status = 'Active'
        AND pl.is_deleted = false
        AND pl.is_archived = false
    ) LOOP
      v_remaining_store_id := (v_employee_home_stores ->> v_pl.id::text)::uuid;

      SELECT s.store_name, s.vcode
      INTO v_remaining_store_name, v_remaining_store_vcode
      FROM public.stores s WHERE s.id = v_remaining_store_id;

      UPDATE public.plantilla
      SET deployment_type   = 'Stationary',
          coverage_group_id = NULL,
          coverage_slot_id  = NULL,
          store_id          = v_remaining_store_id,
          store_name        = v_remaining_store_name,
          vcode             = v_remaining_store_vcode
      WHERE id = v_pl.id;

      IF v_pl.source_employee_import_batch_id IS NOT NULL
        OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        UPDATE public.employee_store_allocations
        SET is_active = false, effective_end = CURRENT_DATE
        WHERE plantilla_id = v_pl.id
          AND is_active = true
          AND store_id <> v_remaining_store_id;

        IF NOT EXISTS (
          SELECT 1 FROM public.employee_store_allocations
          WHERE plantilla_id = v_pl.id
            AND store_id = v_remaining_store_id
            AND is_active = true
        ) THEN
          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          ) VALUES (
            v_pl.id, v_pl.employee_no, NULL,
            v_remaining_store_id, v_remaining_store_vcode, v_remaining_store_name,
            v_pl.account_id, v_pl.group_id,
            1.0, 1,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, p_actor_id
          );
        ELSE
          UPDATE public.employee_store_allocations
          SET roving_group_id    = NULL,
              active_store_count = 1,
              filled_hc          = 1.0
          WHERE plantilla_id = v_pl.id
            AND store_id = v_remaining_store_id
            AND is_active = true;
        END IF;
      ELSE
        UPDATE public.plantilla_store_links psl
        SET status = 'Resigned', deleted_at = now(), unlinked_at = now(), unlinked_by = p_actor_id
        FROM public.stores s
        WHERE psl.vcode = s.vcode
          AND psl.plantilla_id = v_pl.id
          AND s.id <> v_remaining_store_id
          AND psl.deleted_at IS NULL;
      END IF;

      v_employees_converted := v_employees_converted + 1;
      v_notes := v_notes || ARRAY[
        'employee:' || COALESCE(v_pl.employee_name, v_pl.employee_no, v_pl.id::text)
        || '|converted_to_stationary_at:' || COALESCE(v_remaining_store_name, v_remaining_store_id::text)
      ];
    END LOOP;

    -- Archive group store edges
    UPDATE public.coverage_group_stores
    SET archived_at = now(), archived_by = p_actor_id
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND archived_at IS NULL;

    -- Close slots
    UPDATE public.coverage_slots
    SET slot_status = 'closed', updated_at = now()
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND slot_status <> 'closed';

    -- Archive group
    UPDATE public.coverage_groups
    SET archived_at    = now(),
        archived_by    = p_actor_id,
        archive_reason = 'Coverage Request execution: dissolved — employees converted to Stationary'
    WHERE id = p_request.target_coverage_group_id;

    v_group_archived := true;

    -- Reopen vacancies for stores that lost coverage
    IF v_dissolved_store_ids IS NOT NULL
      AND array_length(v_dissolved_store_ids, 1) > 0
    THEN
      FOREACH v_store_id IN ARRAY v_dissolved_store_ids LOOP
        SELECT
          s.store_name,
          s.vcode,
          s.account_id,
          s.group_id,
          a.account_name,
          COALESCE(s.area_city, s.area_province, '') AS area_name
        INTO
          v_store_name_local,
          v_store_vcode,
          v_store_account_id,
          v_store_group_id,
          v_store_account_name,
          v_store_area
        FROM public.stores s
        LEFT JOIN public.accounts a ON a.id = s.account_id
        WHERE s.id = v_store_id;

        v_store_group_id    := COALESCE(v_store_group_id, v_cg_account_group_id);
        v_store_province_id := NULL;
        v_store_chain_id    := NULL;

        IF v_store_vcode IS NULL THEN
          v_notes := v_notes || ARRAY['store ' || v_store_id::text || ' has no vcode; vacancy not created'];
          CONTINUE;
        END IF;

        v_store_position    := COALESCE(v_cg_position_name, 'Unknown');
        v_store_position_id := v_cg_position_id;

        -- Hard guard for position_id validity
        IF NOT EXISTS (
          SELECT 1 FROM public.positions WHERE id = v_store_position_id
        ) THEN
          RAISE EXCEPTION 'Invalid position_id: %', v_store_position_id;
        END IF;

        v_store_employment_type := 'Stationary';

        UPDATE public.vacancies
        SET status              = 'Open',
            is_archived         = false,
            archived_at         = NULL,
            has_pending_closure = false,
            vacant_date         = CURRENT_DATE,
            updated_at          = now()
        WHERE vcode      = v_store_vcode
          AND deleted_at IS NULL
          AND status IN ('Filled', 'Closed', 'Archived', 'Open');

        GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

        IF v_rows_updated = 0 THEN
          INSERT INTO public.vacancies (
            vcode, account, position,
            account_id, chain_id, store_id,
            province_id, area_name, position_id,
            vacant_date, vacancy_type, status,
            source_plantilla_id, store_name,
            created_at, updated_at, required_headcount
          )
          SELECT
            v_store_vcode,
            COALESCE(v_store_account_name, 'UNKNOWN'),
            p.position_name,
            v_store_account_id,
            v_store_chain_id,
            v_store_id,
            v_store_province_id,
            v_store_area,
            p.id,
            CURRENT_DATE,
            'Backfill',
            'Open',
            NULL,
            v_store_name_local,
            now(), now(), 1
          FROM public.positions p
          WHERE p.id = v_store_position_id
          ON CONFLICT DO NOTHING;
        END IF;

        SELECT id INTO v_existing_slot_id
        FROM public.plantilla_slots
        WHERE store_id   = v_store_id
          AND account_id = v_store_account_id
          AND slot_status <> 'closed'
        ORDER BY created_at DESC
        LIMIT 1;

        IF v_existing_slot_id IS NOT NULL THEN
          UPDATE public.plantilla_slots
          SET slot_status                   = 'open',
              employment_type               = 'Stationary',
              is_roving                     = false, -- Bug Fix: reset to false when converted back to stationary
              group_id                      = COALESCE(group_id, v_store_group_id),
              current_occupant_plantilla_id  = NULL,
              closed_at                      = NULL,
              closed_by                      = NULL,
              closure_reason_code            = NULL,
              updated_at                     = now(),
              updated_by                     = p_actor_id
          WHERE id = v_existing_slot_id;

          v_new_slot_id := v_existing_slot_id;
        ELSE
          SELECT id INTO v_existing_slot_id
          FROM public.plantilla_slots
          WHERE store_id   = v_store_id
            AND account_id = v_store_account_id
            AND slot_status = 'closed'
          ORDER BY updated_at DESC
          LIMIT 1;

          IF v_existing_slot_id IS NOT NULL THEN
            UPDATE public.plantilla_slots
            SET slot_status                   = 'open',
                employment_type               = 'Stationary',
                is_roving                     = false, -- Bug Fix: reset to false when converted back to stationary
                group_id                      = COALESCE(group_id, v_store_group_id),
                current_occupant_plantilla_id  = NULL,
                closed_at                      = NULL,
                closed_by                      = NULL,
                closure_reason_code            = NULL,
                legacy_vcode                   = COALESCE(legacy_vcode, v_store_vcode),
                updated_at                     = now(),
                updated_by                     = p_actor_id
            WHERE id = v_existing_slot_id;

            v_new_slot_id := v_existing_slot_id;
          ELSE
            v_new_slot_id := gen_random_uuid();
            INSERT INTO public.plantilla_slots (
              id, store_id, account_id, group_id,
              position, employment_type, is_roving,
              slot_status, legacy_vcode,
              created_by, updated_by, created_at, updated_at
            ) VALUES (
              v_new_slot_id,
              v_store_id, v_store_account_id, v_store_group_id,
              COALESCE(v_store_position, 'Unknown'),
              'Stationary',
              false,
              'open',
              v_store_vcode,
              p_actor_id, p_actor_id, now(), now()
            );
          END IF;
        END IF;

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type,
          old_value, new_value, reason_code,
          performed_by, remarks, created_at
        ) VALUES (
          v_new_slot_id,
          v_store_account_id,
          'coverage_store_removed',
          'occupied_or_closed',
          'open',
          'COVERAGE_STORE_REMOVED',
          p_actor_id,
          'Coverage Request dissolve: store removed from group. Request approved by ' || p_actor_name || '.',
          now()
        );

        v_vacancies_reopened := v_vacancies_reopened + 1;
        v_notes := v_notes || ARRAY[
          'store_dissolved:' || COALESCE(v_store_name_local, v_store_id::text)
          || '|vcode:' || v_store_vcode
          || '|account:' || COALESCE(v_store_account_name, '')
        ];
      END LOOP;
    END IF;

    RETURN jsonb_build_object(
      'structural_execution_enabled',  true,
      'request_type',                  'dissolve_coverage_group',
      'stores_added',                  0,
      'stores_removed',                v_vacancies_reopened,
      'group_archived',                true,
      'below_minimum_action_applied',  null,
      'vacancies_reopened',           v_vacancies_reopened,
      'notes',                         to_jsonb(v_notes)
    );

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── convert_stationary_to_roving ────────────────════════════════════════════
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'convert_stationary_to_roving'::public.request_type THEN
    RAISE EXCEPTION 'convert_stationary_to_roving structural execution not implemented' USING ERRCODE = '0A000';

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── merge_coverage_groups ───────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'merge_coverage_groups'::public.request_type THEN
    v_surviving_cg_id := (p_request.payload ->> 'surviving_coverage_group_id')::uuid;
    v_merged_cg_id    := (p_request.payload ->> 'merged_coverage_group_id')::uuid;

    SELECT coverage_code INTO v_surviving_cg_code
    FROM public.coverage_groups WHERE id = v_surviving_cg_id AND archived_at IS NULL;

    SELECT coverage_code INTO v_merged_cg_code
    FROM public.coverage_groups WHERE id = v_merged_cg_id AND archived_at IS NULL;

    IF v_surviving_cg_code IS NULL OR v_merged_cg_code IS NULL THEN
      RAISE EXCEPTION 'Merge blocked: surviving or merged coverage group not found or archived.' USING ERRCODE = '23514';
    END IF;

    -- Transfer member stores
    UPDATE public.coverage_group_stores
    SET coverage_group_id = v_surviving_cg_id,
        is_anchor          = false
    WHERE coverage_group_id = v_merged_cg_id
      AND archived_at IS NULL;
    GET DIAGNOSTICS v_stores_transferred = ROW_COUNT;

    -- Transfer active employees
    FOR v_pl IN (
      SELECT * FROM public.plantilla
      WHERE coverage_group_id = v_merged_cg_id
        AND status = 'Active'
        AND is_deleted = false
        AND is_archived = false
    ) LOOP
      SELECT COALESCE(MAX(slot_ordinal), 0) + 1 INTO v_slot_ordinal
      FROM public.coverage_slots
      WHERE coverage_group_id = v_surviving_cg_id;

      v_slot_id := gen_random_uuid();

      -- Create slot in surviving group
      INSERT INTO public.coverage_slots (
        id, coverage_group_id, slot_ordinal, slot_status, current_occupant_plantilla_id, created_at, updated_at
      ) VALUES (
        v_slot_id, v_surviving_cg_id, v_slot_ordinal, 'active', v_pl.id, now(), now()
      );

      -- Point employee to surviving group + new slot
      UPDATE public.plantilla
      SET coverage_group_id = v_surviving_cg_id,
          coverage_slot_id  = v_slot_id
      WHERE id = v_pl.id;

      v_employees_transferred := v_employees_transferred + 1;
      v_notes := v_notes || ARRAY[
        'employee:' || COALESCE(v_pl.employee_name, v_pl.employee_no, v_pl.id::text)
        || '|transferred_to_coverage_group:' || v_surviving_cg_code
      ];
    END LOOP;

    -- Close old slots in merged group
    UPDATE public.coverage_slots
    SET slot_status = 'closed', updated_at = now()
    WHERE coverage_group_id = v_merged_cg_id
      AND slot_status <> 'closed';

    -- Archive merged group
    UPDATE public.coverage_groups
    SET archived_at    = now(),
        archived_by    = p_actor_id,
        archive_reason = 'Coverage Request merge: merged into surviving group ' || v_surviving_cg_code
    WHERE id = v_merged_cg_id;

    -- Re-sync all employee store allocations for surviving group's active members
    FOR v_pl IN (
      SELECT * FROM public.plantilla
      WHERE coverage_group_id = v_surviving_cg_id
        AND status = 'Active'
        AND is_deleted = false
        AND is_archived = false
    ) LOOP
      IF v_pl.source_employee_import_batch_id IS NOT NULL
         OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        -- Deactivate old allocations
        UPDATE public.employee_store_allocations
        SET is_active = false, effective_end = CURRENT_DATE
        WHERE plantilla_id = v_pl.id AND is_active = true;

        -- Get list of all member stores now in the surviving group
        SELECT ARRAY_AGG(store_id) INTO v_store_ids
        FROM public.coverage_group_stores
        WHERE coverage_group_id = v_surviving_cg_id AND archived_at IS NULL;

        v_store_count := COALESCE(array_length(v_store_ids, 1), 0);

        -- Insert new allocations for all surviving group stores
        FOREACH v_store_id IN ARRAY v_store_ids LOOP
          SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
          FROM public.stores WHERE id = v_store_id;

          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          ) VALUES (
            v_pl.id, v_pl.employee_no, v_surviving_cg_id,
            v_store_id, v_store_vcode, v_store_name_local,
            v_pl.account_id, v_pl.group_id,
            round(1.0 / v_store_count, 4), v_store_count,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, p_actor_id
          );
        END LOOP;
      ELSE
        -- Live employee: deactivate old store links
        UPDATE public.plantilla_store_links
        SET status = 'Resigned', deleted_at = now(), unlinked_at = now(), unlinked_by = p_actor_id
        WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;

        -- Get list of all member stores now in the surviving group
        SELECT ARRAY_AGG(store_id) INTO v_store_ids
        FROM public.coverage_group_stores
        WHERE coverage_group_id = v_surviving_cg_id AND archived_at IS NULL;

        -- Insert new store links for all surviving group stores
        FOREACH v_store_id IN ARRAY v_store_ids LOOP
          SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
          FROM public.stores WHERE id = v_store_id;

          INSERT INTO public.plantilla_store_links (
            plantilla_id,
            coverage_group_id,
            vcode,
            store_name,
            account,
            status,
            linked_at,
            linked_by,
            created_by,
            updated_by
          ) VALUES (
            v_pl.id,
            v_surviving_cg_id,
            v_store_vcode,
            v_store_name_local,
            (SELECT account_name FROM public.accounts WHERE id = v_pl.account_id),
            'Active',
            now(),
            p_actor_id,
            p_actor_id,
            p_actor_id
          );
        END LOOP;

        PERFORM public.fn_sync_employee_store_allocations(v_pl.employee_no);
      END IF;
    END LOOP;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 'merge_coverage_groups',
      'surviving_coverage_group_id',  v_surviving_cg_id,
      'merged_coverage_group_id',     v_merged_cg_id,
      'stores_transferred',           v_stores_transferred,
      'employees_transferred',        v_employees_transferred,
      'notes',                        to_jsonb(v_notes)
    );

  END IF;

  RETURN jsonb_build_object(
    'structural_execution_enabled', false,
    'error', 'unsupported_request_type'
  );
END;
$function$;

-- 8. reopen_or_create_vacancy_for_plantilla
CREATE OR REPLACE FUNCTION public.reopen_or_create_vacancy_for_plantilla(p_plantilla_id uuid, p_effective_date date, p_vacancy_type text DEFAULT 'Backfill'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_plantilla public.plantilla;
  v_vacancy_id uuid;
BEGIN
  SELECT *
    INTO v_plantilla
  FROM public.plantilla
  WHERE id = p_plantilla_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla not found: %', p_plantilla_id;
  END IF;

  -- Hard guard for position_id validity
  IF NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = v_plantilla.position_id
  ) THEN
    RAISE EXCEPTION 'Invalid position_id: %', v_plantilla.position_id;
  END IF;

  -- VCODE is the manpower slot identity.
  -- Reopen/reactivate existing slot first.
  SELECT id
    INTO v_vacancy_id
  FROM public.vacancies
  WHERE vcode = v_plantilla.vcode
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_vacancy_id IS NOT NULL THEN

    UPDATE public.vacancies
    SET
      status = 'Open',
      vacancy_type = COALESCE(p_vacancy_type, vacancy_type, 'Backfill'),
      vacant_date = p_effective_date,
      source_plantilla_id = v_plantilla.id,
      account = v_plantilla.account,
      account_id = v_plantilla.account_id,
      chain_id = v_plantilla.chain_id,
      store_id = v_plantilla.store_id,
      province_id = v_plantilla.province_id,
      position = v_plantilla.position,
      position_id = v_plantilla.position_id,
      area_name = COALESCE(v_plantilla.area_name_snapshot, v_plantilla.area),
      store_name = v_plantilla.store_name,
      is_archived = FALSE,
      archived_at = NULL,
      deleted_at = NULL,
      has_pending_closure = FALSE,
      updated_at = NOW(),
      updated_by = auth.uid()
    WHERE id = v_vacancy_id;

    RETURN v_vacancy_id;
  END IF;

  INSERT INTO public.vacancies (
    vcode,
    account,
    position,
    account_id,
    chain_id,
    store_id,
    province_id,
    area_name,
    position_id,
    vacant_date,
    vacancy_type,
    status,
    source_plantilla_id,
    store_name,
    created_at,
    updated_at,
    created_by,
    updated_by,
    required_headcount
  )
  SELECT
    v_plantilla.vcode,
    v_plantilla.account,
    p.position_name,
    v_plantilla.account_id,
    v_plantilla.chain_id,
    v_plantilla.store_id,
    v_plantilla.province_id,
    COALESCE(v_plantilla.area_name_snapshot, v_plantilla.area),
    p.id,
    p_effective_date,
    COALESCE(p_vacancy_type, 'Backfill'),
    'Open',
    v_plantilla.id,
    v_plantilla.store_name,
    NOW(),
    NOW(),
    auth.uid(),
    auth.uid(),
    1
  FROM public.positions p
  WHERE p.id = v_plantilla.position_id
  RETURNING id INTO v_vacancy_id;

  RETURN v_vacancy_id;
END;
$function$;

-- 9. fn_plantilla_separation_to_vacancy
CREATE OR REPLACE FUNCTION public.fn_plantilla_separation_to_vacancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link        RECORD;
  v_vac         public.vacancies%ROWTYPE;
  v_esa         RECORD;
  v_new_link_id uuid;
  v_hc          numeric;
  v_resolved_requirement_id uuid;
BEGIN
  -- Trigger filter logic
  IF OLD.status NOT IN ('Active', 'On Leave', 'For Deactivation')
    OR NEW.status NOT IN ('Resigned', 'AWOL', 'Endo', 'Terminated', 'Others',
                          'Inactive', 'Floating', 'For Deactivation')
    OR OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- ── Roving employee path ─────────────────────────────────────────────────
  IF COALESCE(NEW.is_roving, false) THEN

    IF EXISTS (
      SELECT 1 FROM public.plantilla_store_links
       WHERE plantilla_id = NEW.id AND is_active = true
    ) THEN
      FOR v_link IN
        SELECT * FROM public.plantilla_store_links
         WHERE plantilla_id = NEW.id AND is_active = true
      LOOP
        SELECT COALESCE(esa.filled_hc, 1)::numeric INTO v_hc
          FROM public.employee_store_allocations esa
         WHERE esa.plantilla_id        = NEW.id
           AND esa.store_id            = v_link.store_id
           AND esa.is_active           = true
         LIMIT 1;

        v_hc := COALESCE(v_hc, 1);

        IF v_link.vacancy_id IS NOT NULL THEN
          SELECT * INTO v_vac FROM public.vacancies
           WHERE id = v_link.vacancy_id AND deleted_at IS NULL LIMIT 1;
        ELSE
          SELECT * INTO v_vac FROM public.vacancies
           WHERE vcode = v_link.vcode AND deleted_at IS NULL LIMIT 1;
        END IF;

        IF v_vac.id IS NOT NULL THEN
          IF v_vac.status IN ('Filled', 'Closed') THEN
            UPDATE public.vacancies
               SET status         = 'Open',
                   is_archived    = false,
                   archived_at    = NULL,
                   archived_by    = NULL,
                   required_headcount = GREATEST(
                                         COALESCE(required_headcount, 0) + v_hc,
                                         1
                                       ),
                   updated_at     = NOW()
             WHERE id = v_vac.id;
          ELSE
            UPDATE public.vacancies
               SET required_headcount = GREATEST(
                                         COALESCE(required_headcount, 0) + v_hc,
                                         1
                                       ),
                   updated_at = NOW()
             WHERE id = v_vac.id;
          END IF;
        END IF;

        UPDATE public.plantilla_store_links
           SET is_active   = false,
               deactivated_at = NOW()
         WHERE id = v_link.id;

      END LOOP;

    ELSE
      FOR v_esa IN
        SELECT * FROM public.employee_store_allocations
         WHERE plantilla_id = NEW.id AND is_active = true
      LOOP
        v_hc := COALESCE(v_esa.filled_hc, 1)::numeric;

        SELECT * INTO v_vac FROM public.vacancies
         WHERE store_id    = v_esa.store_id
           AND account_id  = NEW.account_id
           AND is_roving   = true
           AND deleted_at  IS NULL
           AND status NOT IN ('Filled', 'Closed', 'Cancelled')
         LIMIT 1;

        IF NOT FOUND THEN
          -- Hard guard for position_id validity
          IF NOT EXISTS (
            SELECT 1 FROM public.positions WHERE id = NEW.position_id
          ) THEN
            RAISE EXCEPTION 'Invalid position_id: %', NEW.position_id;
          END IF;

          INSERT INTO public.vacancies (
            vcode, account, account_id, store_id, position, position_id,
            status, vacancy_type, is_roving, required_headcount,
            source, created_at, updated_at
          )
          SELECT
            v_esa.store_id::text,
            NEW.account,
            NEW.account_id,
            v_esa.store_id,
            p.position_name,
            p.id,
            'Open',
            'Backfill',
            true,
            GREATEST(v_hc, 1),
            'plantilla',
            NOW(),
            NOW()
          FROM public.positions p
          WHERE p.id = NEW.position_id
          RETURNING * INTO v_vac;
        ELSE
          UPDATE public.vacancies
             SET required_headcount = GREATEST(
                                       COALESCE(required_headcount, 0) + v_hc,
                                       1
                                     ),
                 status    = CASE
                               WHEN status IN ('Filled', 'Closed') THEN 'Open'
                               ELSE status
                             END,
                 is_archived = false,
                 archived_at = NULL,
                 archived_by = NULL,
                 updated_at  = NOW()
           WHERE id = v_vac.id
          RETURNING * INTO v_vac;
        END IF;

        INSERT INTO public.plantilla_store_links (
          plantilla_id, store_id, vcode, vacancy_id, is_active
        )
        SELECT NEW.id, v_esa.store_id,
               COALESCE(v_vac.vcode, v_esa.store_id::text),
               v_vac.id, false
         WHERE NOT EXISTS (
           SELECT 1 FROM public.plantilla_store_links psl
            WHERE psl.plantilla_id = NEW.id
              AND psl.store_id     = v_esa.store_id
         )
        RETURNING id INTO v_new_link_id;

        IF v_new_link_id IS NOT NULL THEN
          UPDATE public.plantilla_store_links
             SET deactivated_at = NOW()
           WHERE id = (
             SELECT id FROM public.plantilla_store_links
              WHERE plantilla_id = NEW.id
                AND store_id     = v_esa.store_id
              ORDER BY created_at DESC
              LIMIT 1
           );
        END IF;
      END LOOP;
    END IF;

    UPDATE public.employee_store_allocations
       SET is_active     = false,
           effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
     WHERE plantilla_id = NEW.id
       AND is_active    = true;

    RETURN NEW;
  END IF;

  -- ── Stationary employee path ─────────────────────────────────────────────
  -- Hard guard for position_id validity before reopening or creating vacancy
  IF NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = NEW.position_id
  ) THEN
    RAISE EXCEPTION 'Invalid position_id: %', NEW.position_id;
  END IF;

  PERFORM public.reopen_or_create_vacancy_for_plantilla(
    NEW.id,
    NEW.date_of_separation,
    'Backfill'
  );

  v_resolved_requirement_id := public.resolve_requirement_for_separation(
    NEW.vacancy_requirement_id,
    NEW.store_id,
    NEW.account_id
  );

  IF v_resolved_requirement_id IS NOT NULL THEN
    UPDATE public.vacancy_requirements
       SET hc_filled = GREATEST(0, hc_filled - 1)
     WHERE id = v_resolved_requirement_id;
  END IF;

  UPDATE public.employee_store_allocations
     SET is_active     = false,
         effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
   WHERE plantilla_id = NEW.id
     AND is_active    = true;

  RETURN NEW;
END;
$function$;
