-- Migration: 20260521990100_fix_hc_request_area_ingestion.sql
-- Description: Audit and fix Headcount Request Area carryover and ingestion logic. Maps 'area_province' from the submit JSON payload into 'headcount_requests.area', updates vacancy generation to populate 'province' directly as a fallback, and backfills existing NULL values for SM KALINGA and SM ILOCOS.

-- 1. Redefine submit_headcount_request to store area_province from frontend input
CREATE OR REPLACE FUNCTION public.submit_headcount_request(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role         text := public.get_my_role();
  v_account      accounts%ROWTYPE;
  v_store        stores%ROWTYPE;
  v_position     positions%ROWTYPE;
  v_group        groups%ROWTYPE;
  v_request_id   uuid;
  v_account_id   uuid;
  v_store_id     uuid;
  v_position_id  uuid;
  v_store_name   text;
begin
  if not (public.i_have_full_access() or public.i_am_ops()) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  begin
    v_account_id  := (p_input->>'account_id')::uuid;
    v_store_id    := nullif(trim(coalesce(p_input->>'store_id', '')), '')::uuid;
    v_position_id := (p_input->>'position_id')::uuid;
  exception
    when invalid_text_representation then
      return jsonb_build_object(
        'ok',    false,
        'error', 'invalid_reference',
        'field', 'uuid_cast',
        'detail', sqlerrm
      );
  end;

  v_store_name := nullif(trim(coalesce(
    p_input->>'store_name',
    p_input->>'store_name_snapshot',
    ''
  )), '');
  if v_store_name is null then
    return jsonb_build_object('ok', false, 'error', 'store_name_required', 'field', 'store_name');
  end if;

  select * into v_account from public.accounts where id = v_account_id;
  if v_account.id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'account_id');
  end if;

  if v_store_id is not null then
    select * into v_store from public.stores where id = v_store_id;
    if v_store.id is not null then
      v_store_name := v_store.store_name;
    end if;
  end if;

  select * into v_position from public.positions where id = v_position_id;
  if v_position.id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'position_id');
  end if;

  if not public.i_have_full_access()
     and not (v_account.account_name = any(public.get_my_allowed_accounts())) then
    return jsonb_build_object('ok', false, 'error', 'out_of_scope');
  end if;

  select * into v_group from public.groups where id = v_account.group_id;

  insert into public.headcount_requests (
    account_id, store_id, position_id,
    employment_type, area, request_type,
    headcount_needed, vacant_date, target_fill_date,
    urgency, reason,
    status,
    group_id, account_name_snapshot, store_name_snapshot,
    position_name_snapshot, group_name_snapshot,
    requested_by_user_id, requested_by_name, requested_by_role
  ) values (
    v_account_id, v_store_id, v_position_id,
    coalesce(p_input->>'employment_type', 'Stationary'),
    coalesce(p_input->>'area_province', p_input->>'area'), -- Surgical fix: ingest area_province if area is absent
    coalesce(p_input->>'request_type', 'Replacement'),
    coalesce((p_input->>'headcount_needed')::int, 1),
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
$function$
;

-- 2. Redefine create_plantilla_slot_from_request to set province directly from v_req.area fallback
CREATE OR REPLACE FUNCTION public.create_plantilla_slot_from_request(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role              text := public.get_my_role();
  v_req               public.headcount_requests%ROWTYPE;
  v_account           public.accounts%ROWTYPE;
  v_store             public.stores%ROWTYPE;
  v_position          public.positions%ROWTYPE;
  v_store_name        text;
  v_store_id          uuid;
  v_vcode             text;
  v_vcodes            text[] := ARRAY[]::text[];
  v_plantilla_id      uuid;
  v_vacancy_id        uuid;
  v_first_plantilla_id uuid;
  v_count             integer;
  i                   integer;
  v_triggered_by_id   uuid;
  v_triggered_by_name text;
  v_hrco_user_id      uuid;
  v_hrco_name         text;
  v_group_id          uuid;
  v_group_name        text;
BEGIN
  IF NOT (v_role IN ('Encoder', 'Super Admin', 'Head Admin')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

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

  v_triggered_by_id := public.get_current_profile_id();
  SELECT full_name INTO v_triggered_by_name
  FROM public.users_profile WHERE id = v_triggered_by_id;

  v_hrco_user_id := v_account.hrco_user_id;
  IF v_hrco_user_id IS NOT NULL THEN
    SELECT full_name INTO v_hrco_name
    FROM public.users_profile WHERE id = v_hrco_user_id;
  END IF;

  FOR i IN 1..v_count LOOP
    v_vcode := public.generate_vcode_for_account(v_account.id);
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
    ) VALUES (
      v_vcode, v_account.account_name, v_position.position_name, 'Open',
      v_account.id, v_store_id, v_position.id, v_group_id,
      COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province), v_store_name, COALESCE(v_req.vacant_date, CURRENT_DATE),
      1, NULL,
      CASE WHEN v_req.request_type = 'Replacement' THEN 'Replacement' ELSE 'New' END,
      v_req.employment_type, v_req.urgency, v_req.target_fill_date,
      v_triggered_by_id, v_triggered_by_name,
      v_hrco_user_id, v_hrco_name,
      'hc_request', p_request_id,
      v_store.area_city, COALESCE(v_store.province, NULLIF(TRIM(v_req.area), '')), v_store.store_branch, -- Direct province fallback
      v_group_name, v_group_id,
      v_triggered_by_id, v_triggered_by_id
    ) RETURNING id INTO v_vacancy_id;

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
      v_account.id, v_store_id, COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province), v_position.id,
      v_store_name, v_req.employment_type,
      p_request_id,
      v_group_id,
      v_triggered_by_id, v_triggered_by_id, CURRENT_DATE
    ) RETURNING id INTO v_plantilla_id;

    IF v_first_plantilla_id IS NULL THEN
      v_first_plantilla_id := v_plantilla_id;
    END IF;

    UPDATE public.vacancies
    SET source_plantilla_id = v_plantilla_id,
        updated_by = v_triggered_by_id
    WHERE id = v_vacancy_id;
  END LOOP;

  UPDATE public.headcount_requests
  SET status                   = 'completed',
      vacancy_created          = true,
      slot_created_by_user_id  = v_triggered_by_id,
      slot_created_at          = NOW(),
      created_plantilla_id     = v_first_plantilla_id,
      created_vcode            = CASE WHEN array_length(v_vcodes, 1) >= 1 THEN v_vcodes[1] ELSE NULL END,
      created_vcodes           = v_vcodes
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'ok',               true,
    'request_id',       p_request_id,
    'headcount_created', v_count,
    'vcode_count',      array_length(v_vcodes, 1),
    'vcodes',           v_vcodes,
    'vacancy_created',  true
  );
END;
$function$
;

-- 3. Redefine create_vacancy_from_headcount_request to set province directly from v_req.area fallback
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
  ) VALUES (
    v_req.created_vcode, v_account.account_name, v_position.position_name, 'Open',
    v_account.id, v_store_id, v_position.id, v_group_id,
    COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province), v_store_name, COALESCE(v_req.vacant_date, CURRENT_DATE),
    v_req.headcount_needed, v_req.created_plantilla_id,
    CASE WHEN v_req.request_type = 'Replacement' THEN 'Replacement' ELSE 'New' END,
    v_req.employment_type, v_req.urgency, v_req.target_fill_date,
    v_triggered_by_id, v_triggered_by_name,
    v_hrco_user_id, v_hrco_name,
    'hc_request', p_request_id,
    v_store.area_city, COALESCE(v_store.province, NULLIF(TRIM(v_req.area), '')), v_store.store_branch, -- Direct province fallback
    v_group_name, v_group_id,
    v_triggered_by_id, v_triggered_by_id
  );

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
$function$
;

-- 4. Retroactive backfill for existing rows
-- SM KALINGA request backfill
UPDATE public.headcount_requests
SET area = 'Kalinga'
WHERE id = '50f81045-ecd2-483b-9eb5-c3d37a4f6831'
  AND area IS NULL;

-- SM ILOCOS request backfill
UPDATE public.headcount_requests
SET area = 'Ilocos'
WHERE id = '595442a4-be61-4dd9-bd1c-077566cff423'
  AND area IS NULL;

-- Vacancies backfill for SM KALINGA (VCAG5_0011, VCAG5_0012, VCAG5_0013, VCAG5_0014, VCAG5_0015)
UPDATE public.vacancies
SET area_name = 'Kalinga',
    province = 'Kalinga'
WHERE source_headcount_request_id = '50f81045-ecd2-483b-9eb5-c3d37a4f6831';

-- Vacancies backfill for SM ILOCOS (VCAG5_0010)
UPDATE public.vacancies
SET area_name = 'Ilocos',
    province = 'Ilocos'
WHERE source_headcount_request_id = '595442a4-be61-4dd9-bd1c-077566cff423';

-- Plantilla backfill for SM KALINGA
UPDATE public.plantilla
SET area = 'Kalinga'
WHERE source_headcount_request_id = '50f81045-ecd2-483b-9eb5-c3d37a4f6831';

-- Plantilla backfill for SM ILOCOS
UPDATE public.plantilla
SET area = 'Ilocos'
WHERE source_headcount_request_id = '595442a4-be61-4dd9-bd1c-077566cff423';
