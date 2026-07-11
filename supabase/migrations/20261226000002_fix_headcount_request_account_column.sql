-- ============================================================
-- ohm#hc_reduce_003 — Fix submit_headcount_request regression
-- Migration: 20261226000002_fix_headcount_request_account_column.sql
-- ============================================================
-- Migration 20261226000001 replaced submit_headcount_request with a
-- version that referenced non-existent columns:
--   account_name, store_name, position_name, area_province,
--   area_city_municipality, requested_by
-- The actual headcount_requests table uses:
--   account_name_snapshot, store_name_snapshot, position_name_snapshot,
--   area, city_municipality, requested_by_user_id / requested_by_name /
--   requested_by_role
--
-- This migration restores the correct function body (from
-- 20261024000000_hc_request_workforce_type_coverage_group.sql) while
-- preserving the HC Reduction Ops-only guard that was the only valid
-- change introduced by 20261226000001.
--
-- HC Reduction business rules, approval workflow, slot reduction
-- logic, execute_hc_reduction, execute_pool_hc_reduction, and
-- create_pool_hc_reduction_request are NOT touched.
-- ============================================================

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

  return jsonb_build_object('ok', true, 'request_id', v_request_id, 'status', 'pending');
end
$function$;

COMMENT ON FUNCTION public.submit_headcount_request(jsonb) IS
  'Creates a headcount request (stationary or roving). '
  'HC Reduction is Ops-only — HA/SA may approve via execute_hc_reduction but cannot submit. '
  'Regression fix for ohm#hc_reduce_003: restores correct snapshot column names '
  '(account_name_snapshot, store_name_snapshot, position_name_snapshot, city_municipality).';
