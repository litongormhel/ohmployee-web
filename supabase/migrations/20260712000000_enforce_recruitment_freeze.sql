-- ─────────────────────────────────────────────────────────────────────────────
-- OHM's Safespace: Recruitment Freeze Gated Enforcement (Phase 2A)
-- Migration: 20260712000000_enforce_recruitment_freeze.sql
-- Enforces recruitment freeze on vacancy creation, headcount request,
-- VCODE generation, and vacancy approval actions.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Define updated fn_assert_freeze_inactive ───────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_assert_freeze_inactive(p_freeze_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.fn_check_freeze_active(p_freeze_key) THEN
    IF public.fn_check_freeze_active('read_only_emergency') THEN
      RAISE EXCEPTION 'System is in Read-Only Emergency Mode. Operations are temporarily suspended.'
        USING ERRCODE = 'P0001';
    ELSIF p_freeze_key = 'recruitment_freeze' THEN
      RAISE EXCEPTION 'Recruitment operations are temporarily frozen by System Administration.'
        USING ERRCODE = 'P0001';
    ELSE
      RAISE EXCEPTION 'This operation is suspended due to an active %.', replace(p_freeze_key, '_', ' ')
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
END;
$$;

-- ── 2. Gate submit_headcount_request ──────────────────────────────────────────
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

  -- Enforce Recruitment Freeze
  PERFORM public.fn_assert_freeze_inactive('recruitment_freeze');

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
    employment_type, area, city_municipality, request_type,
    headcount_needed, vacant_date, target_fill_date,
    urgency, reason,
    status,
    group_id, account_name_snapshot, store_name_snapshot,
    position_name_snapshot, group_name_snapshot,
    requested_by_user_id, requested_by_name, requested_by_role
  ) values (
    v_account_id, v_store_id, v_position_id,
    coalesce(p_input->>'employment_type', 'Stationary'),
    coalesce(p_input->>'area_province', p_input->>'area'),
    nullif(trim(coalesce(p_input->>'area_city', '')), ''),
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

-- ── 3. Gate create_plantilla_slot_from_request ────────────────────────────────
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

  -- Enforce Recruitment Freeze
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
      COALESCE(v_store.area_city, v_req.city_municipality),
      COALESCE(v_store.province, NULLIF(TRIM(v_req.area), '')),
      v_store.store_branch,
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

-- ── 4. Gate create_vacancy_from_headcount_request ─────────────────────────────
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
    COALESCE(v_store.area_city, v_req.city_municipality),
    COALESCE(v_store.province, NULLIF(TRIM(v_req.area), '')),
    v_store.store_branch,
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

-- ── 5. Gate generate_vcodes_for_request ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.generate_vcodes_for_request(p_vacancy_request_id uuid, p_account_code text, p_group_code text, p_slots integer)
 RETURNS TABLE(vcode_id uuid, vcode text, sequence_num integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_prefix        TEXT;
  v_seq           INT;
  v_vcode         TEXT;
  v_id            UUID;
  v_lock_key      BIGINT;
  v_generated     INT := 0;
  v_already       INT;
BEGIN
  -- Enforce Recruitment Freeze
  PERFORM public.fn_assert_freeze_inactive('recruitment_freeze');

  -- Validate group_code
  IF p_group_code NOT IN ('G1','G2','G3','G4','G5') THEN
    RAISE EXCEPTION 'Invalid group_code: %. Must be G1–G5.', p_group_code;
  END IF;

  -- Validate slots
  IF p_slots < 1 OR p_slots > 100 THEN
    RAISE EXCEPTION 'slots must be between 1 and 100.';
  END IF;

  -- Guard: already fully generated
  SELECT COUNT(*) INTO v_already
  FROM vcodes
  WHERE vacancy_request_id = p_vacancy_request_id;

  IF v_already >= p_slots THEN
    RAISE EXCEPTION 'VCodes already fully generated for this request (% / %).', v_already, p_slots;
  END IF;

  -- Advisory lock — prevents race condition per scope
  v_lock_key := hashtext(p_account_code || '::' || p_group_code);
  PERFORM pg_advisory_xact_lock(v_lock_key);

  v_prefix := p_account_code || '-' || p_group_code;

  LOOP
    EXIT WHEN v_generated >= p_slots;

    -- Atomic increment via vcode_sequences
    INSERT INTO vcode_sequences (prefix, last_seq, updated_at)
    VALUES (v_prefix, 1, NOW())
    ON CONFLICT (prefix) DO UPDATE
      SET last_seq   = vcode_sequences.last_seq + 1,
          updated_at = NOW()
    RETURNING last_seq INTO v_seq;

    v_vcode := v_prefix || '-' || LPAD(v_seq::TEXT, 4, '0');
    v_id    := gen_random_uuid();

    INSERT INTO vcodes (
      id, vacancy_request_id, account_code,
      group_code, sequence_number, vcode, status
    ) VALUES (
      v_id, p_vacancy_request_id, p_account_code,
      p_group_code, v_seq, v_vcode, 'available'
    );

    vcode_id     := v_id;
    vcode        := v_vcode;
    sequence_num := v_seq;
    RETURN NEXT;

    v_generated := v_generated + 1;
  END LOOP;
END;
$function$
;

-- ── 6. Gate generate_vcodes_from_request ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.generate_vcodes_from_request(p_vacancy_request_id uuid)
 RETURNS TABLE(vcode_id uuid, vcode text, sequence_num integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_account_code  TEXT;
  v_group_code    TEXT;
  v_slots         INT;
  v_account_name  TEXT;
BEGIN
  -- Enforce Recruitment Freeze
  PERFORM public.fn_assert_freeze_inactive('recruitment_freeze');

  -- Pull slots + account name from vacancy_request
  SELECT no_of_slots, account
  INTO v_slots, v_account_name
  FROM vacancy_requests
  WHERE id = p_vacancy_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Vacancy request not found: %', p_vacancy_request_id;
  END IF;

  IF v_slots IS NULL OR v_slots < 1 THEN
    RAISE EXCEPTION 'no_of_slots is null or invalid on this request.';
  END IF;

  -- Resolve account_code + group_code from account name
  SELECT a.account_code, g.group_code
  INTO v_account_code, v_group_code
  FROM accounts a
  JOIN groups g ON a.group_id = g.id
  WHERE LOWER(TRIM(a.account_name)) = LOWER(TRIM(v_account_name))
  LIMIT 1;

  IF v_account_code IS NULL THEN
    RAISE EXCEPTION 'Cannot resolve account_code for account: "%". Check accounts table.', v_account_name;
  END IF;

  -- Delegate to core generator
  RETURN QUERY
  SELECT r.vcode_id, r.vcode, r.sequence_num
  FROM generate_vcodes_for_request(
    p_vacancy_request_id,
    v_account_code,
    v_group_code,
    v_slots
  ) r;
END;
$function$
;

-- ── 7. Gate approve_vacancy_request_auto_vcodes ────────────────────────────────
CREATE OR REPLACE FUNCTION public.approve_vacancy_request_auto_vcodes(p_request_id uuid, p_reviewer_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role text := public.get_my_role();
  v_role_level int := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_actor_name text := public.get_my_full_name();
  v_request public.vacancy_requests%ROWTYPE;
  v_old jsonb;
  v_slots int;
  v_existing_vcodes int;
  v_generated jsonb := '[]'::jsonb;
  v_vcode text;
  v_vcodes text[];
  v_vacancy_ids uuid[];
  v_vacancy_id uuid;
  v_already_approved boolean;
BEGIN
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('Encoder')
  ) THEN
    RAISE EXCEPTION 'forbidden: Super Admin, Head Admin, or Encoder required'
      USING ERRCODE = '42501';
  END IF;

  -- Enforce Recruitment Freeze
  PERFORM public.fn_assert_freeze_inactive('recruitment_freeze');

  SELECT *
    INTO v_request
    FROM public.vacancy_requests
   WHERE id = p_request_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'vacancy request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_request.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: vacancy request is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(v_request.status, 'Pending') = 'Rejected' THEN
    RAISE EXCEPTION 'cannot approve rejected vacancy request %', p_request_id
      USING ERRCODE = '22023';
  END IF;

  IF COALESCE(v_request.status, 'Pending') NOT IN ('Pending', 'Approved') THEN
    RAISE EXCEPTION 'cannot approve vacancy request % from status %', p_request_id, v_request.status
      USING ERRCODE = '22023';
  END IF;

  v_already_approved := COALESCE(v_request.status, 'Pending') = 'Approved';

  v_slots := COALESCE(v_request.no_of_slots, 1);
  IF v_slots < 1 THEN
    RAISE EXCEPTION 'vacancy request % has invalid no_of_slots %', p_request_id, v_request.no_of_slots
      USING ERRCODE = '22023';
  END IF;

  SELECT COUNT(*)
    INTO v_existing_vcodes
    FROM public.vcodes
   WHERE vacancy_request_id = p_request_id;

  IF v_existing_vcodes = 0 THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY g.sequence_num), '[]'::jsonb)
      INTO v_generated
      FROM public.generate_vcodes_from_request(p_request_id) AS g;
  ELSIF v_existing_vcodes <> v_slots THEN
    RAISE EXCEPTION 'unexpected VCode count detected for request % (%/%). Resolve before approval.',
      p_request_id, v_existing_vcodes, v_slots
      USING ERRCODE = '23505';
  END IF;

  SELECT ARRAY_AGG(v.vcode ORDER BY v.sequence_number)
    INTO v_vcodes
    FROM public.vcodes v
   WHERE v.vacancy_request_id = p_request_id;

  IF COALESCE(array_length(v_vcodes, 1), 0) < v_slots THEN
    RAISE EXCEPTION 'VCode generation failed for request %', p_request_id
      USING ERRCODE = '23505';
  END IF;

  IF NOT v_already_approved THEN
    v_old := to_jsonb(v_request);

    UPDATE public.vacancy_requests
       SET status = 'Approved',
           reviewed_by = v_actor_name,
           reviewed_at = NOW(),
           reviewer_remarks = p_reviewer_remarks,
           vcode_created = v_vcodes[1],
           updated_at = NOW()
     WHERE id = p_request_id
     RETURNING * INTO v_request;
  END IF;

  FOREACH v_vcode IN ARRAY v_vcodes LOOP
    INSERT INTO public.vacancies (
      vcode,
      account,
      position,
      status,
      vacancy_type,
      store_name,
      vacant_date,
      required_headcount,
      has_penalty,
      is_archived,
      has_pending_closure
    ) VALUES (
      v_vcode,
      v_request.account,
      v_request.position,
      'Open',
      v_request.vacancy_type,
      v_request.store_name,
      v_request.date_needed,
      1,
      COALESCE(v_request.has_penalty, false),
      false,
      false
    )
    ON CONFLICT (vcode) DO UPDATE
      SET updated_at = NOW()
      WHERE public.vacancies.status = 'Open'
        AND COALESCE(public.vacancies.is_archived, false) = false
        AND public.vacancies.deleted_at IS NULL
    RETURNING id INTO v_vacancy_id;

    IF v_vacancy_id IS NULL THEN
      SELECT id INTO v_vacancy_id
        FROM public.vacancies
       WHERE vcode = v_vcode
         AND status = 'Open'
         AND COALESCE(is_archived, false) = false
         AND deleted_at IS NULL;
    END IF;

    IF v_vacancy_id IS NULL THEN
      RAISE EXCEPTION 'active vacancy could not be created or reused for VCode %', v_vcode
        USING ERRCODE = '23505';
    END IF;

    v_vacancy_ids := array_append(v_vacancy_ids, v_vacancy_id);
  END LOOP;

  IF NOT v_already_approved THEN
    PERFORM public.log_audit_event(
      'Vacancy.Request',
      'APPROVAL',
      p_request_id,
      v_old,
      jsonb_build_object(
        'status', 'Approved',
        'reviewed_by', v_actor_name,
        'reviewed_by_profile_id', v_profile_id,
        'reviewer_remarks', p_reviewer_remarks,
        'vcodes', v_vcodes,
        'vacancy_ids', v_vacancy_ids,
        'business_action', 'APPROVE_VACANCY_REQUEST_AUTO_VCODES'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'request_id', p_request_id,
    'status', 'Approved',
    'reviewed_by', v_request.reviewed_by,
    'reviewed_at', v_request.reviewed_at,
    'vcodes', v_vcodes,
    'vcode_created', v_vcodes[1],
    'vacancy_ids', v_vacancy_ids,
    'generated', v_generated,
    'already_approved', v_already_approved
  );
END;
$function$
;
