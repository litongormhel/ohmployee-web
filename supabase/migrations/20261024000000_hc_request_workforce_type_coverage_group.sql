-- OHM2026_0096 - HC Request workforce type + Coverage Group integration
--
-- Phase 4: Coverage Architecture v2
-- - HC Request remains the only new roving-demand creation path.
-- - Stationary requests target a Store.
-- - Roving requests target an existing Coverage Group.
-- - Coverage Requests remain structure-only and are not touched here.

ALTER TABLE public.headcount_requests
  ADD COLUMN IF NOT EXISTS workforce_type text NOT NULL DEFAULT 'stationary',
  ADD COLUMN IF NOT EXISTS coverage_group_id uuid,
  ADD COLUMN IF NOT EXISTS coverage_group_code_snapshot text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'headcount_requests_workforce_type_check'
  ) THEN
    ALTER TABLE public.headcount_requests
      ADD CONSTRAINT headcount_requests_workforce_type_check
      CHECK (workforce_type IN ('stationary', 'roving', 'floating'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'headcount_requests_coverage_group_fkey'
  ) THEN
    ALTER TABLE public.headcount_requests
      ADD CONSTRAINT headcount_requests_coverage_group_fkey
      FOREIGN KEY (coverage_group_id)
      REFERENCES public.coverage_groups(id)
      ON DELETE RESTRICT
      NOT VALID;
  END IF;
END $$;

COMMENT ON COLUMN public.headcount_requests.workforce_type IS
  'Coverage Architecture v2 discriminator. stationary=Store HC Request, roving=Coverage Group HC Request, floating=reserved placeholder only.';
COMMENT ON COLUMN public.headcount_requests.coverage_group_id IS
  'Required for roving HC Requests. Points to the Coverage Group whose vacancy/slot surface receives the approved people count.';
COMMENT ON COLUMN public.headcount_requests.coverage_group_code_snapshot IS
  'Display snapshot for the target Coverage Group at HC Request submission time.';

CREATE OR REPLACE FUNCTION public.submit_headcount_request(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role              text := public.get_my_role();
  v_account           accounts%ROWTYPE;
  v_store             stores%ROWTYPE;
  v_position          positions%ROWTYPE;
  v_group             groups%ROWTYPE;
  v_coverage_group    coverage_groups%ROWTYPE;
  v_request_id        uuid;
  v_account_id        uuid;
  v_store_id          uuid;
  v_position_id       uuid;
  v_coverage_group_id uuid;
  v_store_name        text;
  v_workforce_type    text;
  v_headcount_needed  integer;
begin
  if not (public.i_have_full_access() or public.i_am_ops()) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  v_workforce_type := lower(nullif(trim(coalesce(
    p_input->>'workforce_type',
    p_input->>'employment_type',
    'stationary'
  )), ''));

  if v_workforce_type not in ('stationary', 'roving', 'floating') then
    return jsonb_build_object('ok', false, 'error', 'invalid_workforce_type');
  end if;

  if v_workforce_type = 'floating' then
    return jsonb_build_object(
      'ok', false,
      'error', 'floating_workforce_not_enabled',
      'message', 'Floating workforce is reserved for a future phase.'
    );
  end if;

  begin
    v_account_id  := (p_input->>'account_id')::uuid;
    v_store_id    := nullif(trim(coalesce(p_input->>'store_id', '')), '')::uuid;
    v_position_id := (p_input->>'position_id')::uuid;
    v_coverage_group_id := nullif(trim(coalesce(p_input->>'coverage_group_id', '')), '')::uuid;
    v_headcount_needed := coalesce((p_input->>'headcount_needed')::int, 1);
  exception
    when invalid_text_representation then
      return jsonb_build_object(
        'ok',    false,
        'error', 'invalid_reference',
        'field', 'uuid_cast',
        'detail', sqlerrm
      );
  end;

  if v_headcount_needed < 1 then
    return jsonb_build_object('ok', false, 'error', 'invalid_headcount_needed');
  end if;

  select * into v_account from public.accounts where id = v_account_id;
  if v_account.id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'account_id');
  end if;

  select * into v_position from public.positions where id = v_position_id;
  if v_position.id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'position_id');
  end if;

  if not public.i_have_full_access()
     and not (v_account.account_name = any(public.get_my_allowed_accounts())) then
    return jsonb_build_object('ok', false, 'error', 'out_of_scope');
  end if;

  if v_workforce_type = 'stationary' then
    if v_store_id is null then
      return jsonb_build_object('ok', false, 'error', 'store_required_for_stationary');
    end if;

    select * into v_store
    from public.stores
    where id = v_store_id
      and account_id = v_account_id
      and coalesce(is_active, true) = true;

    if v_store.id is null then
      return jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'store_id');
    end if;

    v_store_name := nullif(trim(v_store.store_name), '');
    if v_store_name is null then
      return jsonb_build_object('ok', false, 'error', 'store_name_required', 'field', 'store_name');
    end if;
  else
    if v_coverage_group_id is null then
      return jsonb_build_object('ok', false, 'error', 'coverage_group_required_for_roving');
    end if;

    select * into v_coverage_group
    from public.coverage_groups
    where id = v_coverage_group_id
      and account_id = v_account_id
      and archived_at is null;

    if v_coverage_group.id is null then
      return jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'coverage_group_id');
    end if;

    if v_coverage_group.position_id <> v_position_id then
      return jsonb_build_object('ok', false, 'error', 'coverage_group_position_mismatch');
    end if;

    v_store_id := null;
    v_store_name := v_coverage_group.coverage_code;
  end if;

  select * into v_group from public.groups where id = v_account.group_id;

  insert into public.headcount_requests (
    account_id, store_id, position_id,
    employment_type, workforce_type, coverage_group_id, coverage_group_code_snapshot,
    area, city_municipality, request_type,
    headcount_needed, vacant_date, target_fill_date,
    urgency, reason,
    status,
    group_id, account_name_snapshot, store_name_snapshot,
    position_name_snapshot, group_name_snapshot,
    requested_by_user_id, requested_by_name, requested_by_role
  ) values (
    v_account_id, v_store_id, v_position_id,
    coalesce(p_input->>'employment_type', initcap(v_workforce_type)),
    v_workforce_type,
    case when v_workforce_type = 'roving' then v_coverage_group_id else null end,
    case when v_workforce_type = 'roving' then v_coverage_group.coverage_code else null end,
    coalesce(p_input->>'area_province', p_input->>'area', v_coverage_group.area_name),
    nullif(trim(coalesce(p_input->>'area_city', '')), ''),
    coalesce(p_input->>'request_type', 'Replacement'),
    v_headcount_needed,
    nullif(p_input->>'vacant_date', '')::date,
    nullif(p_input->>'target_fill_date', '')::date,
    coalesce(p_input->>'urgency', 'Medium'),
    p_input->>'reason',
    'pending',
    v_account.group_id, v_account.account_name, v_store_name,
    v_position.position_name, v_group.group_name,
    public.get_current_profile_id(), public.get_my_full_name(), v_role
  ) returning id into v_request_id;

  return jsonb_build_object(
    'ok',         true,
    'request_id', v_request_id,
    'status',     'pending'
  );
end
$function$;

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

  IF lower(coalesce(v_req.workforce_type, 'stationary')) = 'roving' THEN
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
    SET status = 'completed',
        vacancy_created = true,
        slot_created_by_user_id = v_triggered_by_id,
        slot_created_at = NOW(),
        coverage_group_code_snapshot = COALESCE(coverage_group_code_snapshot, v_coverage_group.coverage_code),
        created_vcode = NULL,
        created_vcodes = ARRAY[]::text[]
    WHERE id = p_request_id;

    RETURN jsonb_build_object(
      'ok', true,
      'request_id', p_request_id,
      'headcount_created', v_count,
      'workforce_type', 'roving',
      'coverage_group_id', v_coverage_group.id,
      'coverage_code', v_coverage_group.coverage_code,
      'coverage_slots_created', v_count,
      'vacancy_created', true
    );
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

  v_group_id := COALESCE(v_req.group_id, v_account.group_id);
  SELECT group_name INTO v_group_name FROM public.groups WHERE id = v_group_id;

  v_hrco_user_id := v_account.hrco_user_id;
  IF v_hrco_user_id IS NOT NULL THEN
    SELECT full_name INTO v_hrco_name
    FROM public.users_profile WHERE id = v_hrco_user_id;
  END IF;

  v_vcode  := public.generate_vcode_for_account(v_account.id);
  v_vcodes := ARRAY[v_vcode];

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

  UPDATE public.vacancies
  SET source_plantilla_id = v_first_plantilla_id,
      updated_by          = v_triggered_by_id
  WHERE id = v_vacancy_id;

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
  SET status                   = 'completed',
      vacancy_created          = true,
      slot_created_by_user_id  = v_triggered_by_id,
      slot_created_at          = NOW(),
      created_plantilla_id     = v_first_plantilla_id,
      created_vcode            = v_vcode,
      created_vcodes           = v_vcodes
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'ok',                true,
    'request_id',        p_request_id,
    'headcount_created', v_count,
    'workforce_type',    'stationary',
    'vcode_count',       1,
    'vcodes',            v_vcodes,
    'vacancy_created',   true,
    'slot_result',       v_slot_result
  );
END;
$function$;
