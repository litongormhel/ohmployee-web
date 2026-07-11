-- ============================================================
-- ohm#hc_reduce_002 — Ops-only guard for HC Reduction submission
-- Migration: 20261226000001_hc_reduction_ops_guard.sql
-- ============================================================
-- Adds enforcement that HC Reduction requests may only be
-- SUBMITTED by Ops roles (om, hrco, atl, tl). HA/SA may
-- APPROVE (via execute_hc_reduction / execute_pool_hc_reduction)
-- but must not create HC Reduction requests themselves unless
-- they also satisfy i_am_ops().
--
-- Sections:
--   §1  Patch submit_headcount_request: reject HC Reduction for non-Ops
--   §2  Patch create_pool_hc_reduction_request: reject for non-Ops
-- ============================================================


-- ============================================================
-- §1  Patch submit_headcount_request
-- ============================================================
-- Adds a single guard after the existing RBAC check: if the
-- request_type is 'HC Reduction' the caller must be i_am_ops().
-- No other logic is changed.

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

  -- HC Reduction is Ops-only: HA/SA may approve but not submit.
  if lower(coalesce(p_input->>'request_type', '')) = 'hc reduction'
     and not public.i_am_ops() then
    return jsonb_build_object(
      'ok',    false,
      'error', 'forbidden',
      'hint',  'HC Reduction requests may only be submitted by Ops roles'
    );
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
    from public.stores where id = v_store_id;
    if v_store.id is null then
      return jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'store_id');
    end if;

    v_store_name := v_store.store_name;

  elsif v_workforce_type = 'roving' then
    if v_coverage_group_id is null then
      return jsonb_build_object('ok', false, 'error', 'coverage_group_required_for_roving');
    end if;

    select * into v_coverage_group
    from public.coverage_groups where id = v_coverage_group_id;
    if v_coverage_group.id is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'invalid_reference',
        'field', 'coverage_group_id'
      );
    end if;

    v_store_name := v_coverage_group.group_code;
  end if;

  insert into public.headcount_requests (
    account_id,
    account_name,
    store_id,
    store_name,
    position_id,
    position_name,
    area_province,
    area_city_municipality,
    employment_type,
    workforce_type,
    request_type,
    headcount_needed,
    vacant_date,
    target_fill_date,
    urgency,
    reason,
    requested_by,
    coverage_group_id
  ) values (
    v_account_id,
    v_account.account_name,
    v_store_id,
    v_store_name,
    v_position_id,
    v_position.position_name,
    p_input->>'area_province',
    p_input->>'area_city',
    p_input->>'employment_type',
    v_workforce_type,
    coalesce(p_input->>'request_type', 'Replacement'),
    v_headcount_needed,
    nullif(trim(coalesce(p_input->>'vacant_date', '')), ''),
    nullif(trim(coalesce(p_input->>'target_fill_date', '')), ''),
    coalesce(p_input->>'urgency', 'Normal'),
    p_input->>'reason',
    p_input->>'requested_by',
    v_coverage_group_id
  )
  returning id into v_request_id;

  return jsonb_build_object('ok', true, 'request_id', v_request_id);
end;
$function$;


-- ============================================================
-- §2  Patch create_pool_hc_reduction_request
-- ============================================================
-- Tighten the RBAC guard from (i_have_full_access OR i_am_ops)
-- to i_am_ops only, enforcing Ops-only submission for pool HC
-- Reduction. HA/SA approve via execute_pool_hc_reduction.

CREATE OR REPLACE FUNCTION public.create_pool_hc_reduction_request(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_role              text := public.get_my_role();
  v_caller_id         uuid := public.get_current_profile_id();
  v_caller_name       text;
  v_pool_type         public.workforce_pool_types%ROWTYPE;
  v_pool_account      public.accounts%ROWTYPE;
  v_op_account        public.accounts%ROWTYPE;
  v_pool_type_id      uuid;
  v_requesting_acct   uuid;
  v_op_acct_id        uuid;
  v_headcount         integer;
  v_request_id        uuid;
  v_priority          text;
BEGIN
  -- HC Reduction is Ops-only: HA/SA may approve but not submit.
  IF NOT public.i_am_ops() THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'forbidden',
      'hint',  'HC Reduction requests may only be submitted by Ops roles'
    );
  END IF;

  BEGIN
    v_pool_type_id    := (p_input->>'pool_type_id')::uuid;
    v_requesting_acct := (p_input->>'requesting_account_id')::uuid;
    v_op_acct_id      := nullif(trim(coalesce(p_input->>'operational_account_id','')),  '')::uuid;
    v_headcount       := coalesce((p_input->>'headcount_needed')::int, 1);
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_uuid');
  END;

  IF v_headcount < 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_headcount_needed');
  END IF;

  SELECT * INTO v_pool_type FROM public.workforce_pool_types WHERE id = v_pool_type_id;
  IF v_pool_type.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_pool_type_id');
  END IF;

  SELECT * INTO v_pool_account FROM public.accounts WHERE id = v_requesting_acct;
  IF v_pool_account.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_requesting_account_id');
  END IF;

  IF v_op_acct_id IS NOT NULL THEN
    SELECT * INTO v_op_account FROM public.accounts WHERE id = v_op_acct_id;
    IF v_op_account.id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_operational_account_id');
    END IF;
    -- Scope guard: Ops must own the operational account
    IF NOT (v_op_account.account_name = ANY(public.get_my_allowed_accounts())) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'out_of_scope');
    END IF;
  END IF;

  v_priority := COALESCE(nullif(trim(p_input->>'priority'), ''), 'normal');
  IF v_priority NOT IN ('normal', 'urgent', 'critical') THEN
    v_priority := 'normal';
  END IF;

  SELECT full_name INTO v_caller_name
  FROM public.users_profile WHERE id = v_caller_id;

  INSERT INTO public.workforce_pool_requests (
    pool_type_id,
    requesting_account_id,
    requesting_account,
    headcount_needed,
    priority,
    reason,
    status,
    request_type,
    is_ops_request,
    operational_account_id,
    operational_account_name,
    is_global_pool_request,
    created_by,
    created_by_name
  ) VALUES (
    v_pool_type_id,
    v_requesting_acct,
    v_pool_account.account_name,
    v_headcount,
    v_priority,
    p_input->>'reason',
    'pending',
    'HC Reduction',
    (v_op_acct_id IS NOT NULL),
    v_op_acct_id,
    v_op_account.account_name,
    (v_op_acct_id IS NULL),
    v_caller_id::text,
    v_caller_name
  )
  RETURNING id INTO v_request_id;

  RETURN jsonb_build_object(
    'ok',        true,
    'request_id', v_request_id,
    'status',    'pending'
  );
END;
$$;

COMMENT ON FUNCTION public.create_pool_hc_reduction_request(jsonb) IS
  'Submits a MOSES HQ HC Reduction request (always pending, requires HA/SA approval). '
  'Ops roles only — HA/SA approve via execute_pool_hc_reduction. '
  'Does NOT create any vacancies or pool slots. ohm#hc_reduce_001, ohm#hc_reduce_002.';

REVOKE ALL ON FUNCTION public.create_pool_hc_reduction_request(jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_pool_hc_reduction_request(jsonb) TO authenticated;
