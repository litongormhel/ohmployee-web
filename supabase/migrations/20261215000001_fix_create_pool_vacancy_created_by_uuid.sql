-- =============================================================================
-- Migration: 20260615000000_fix_create_pool_vacancy_created_by_uuid.sql
-- Fix: create_pool_vacancy RPC passed v_caller_name (text) into created_by (uuid)
-- columns on workforce_pool_requests, vacancies, and workforce_pool_slots,
-- causing PostgrestException 42804 on every submission.
-- Solution: capture auth.uid() into v_caller_id (uuid) and use it for all
-- created_by fields; v_caller_name is kept only for text display columns.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_pool_vacancy(
  p_pool_type_code        text,
  p_position_id           uuid,
  p_requesting_account_id uuid,
  p_requesting_store_id   uuid    DEFAULT NULL::uuid,
  p_headcount_needed      integer DEFAULT 1,
  p_priority              text    DEFAULT 'normal'::text,
  p_reason                text    DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role_level            int;
  v_caller_id             uuid;   -- auth.uid() for created_by (uuid) columns
  v_caller_name           text;   -- full name for display / approved_by columns
  v_pool_type_id          uuid;
  v_moses_hq_id           uuid;
  v_requesting_acct_name  text;
  v_requesting_store_name text;
  v_position_name         text;
  v_req_group_id          uuid;
  v_pool_request_id       uuid;
  v_vcode                 text;
  v_vacancy_id            uuid;
  v_created_vcodes        text[] := '{}';
  v_created_ids           uuid[] := '{}';
  i                       int;
BEGIN
  v_role_level := public.get_my_role_level();
  IF v_role_level IS NULL OR v_role_level NOT IN (100, 90, 30) THEN
    RAISE EXCEPTION 'Unauthorized: create_pool_vacancy requires Data Team access (SA/HA/Encoder)';
  END IF;

  -- Capture caller identity — uuid for FK/created_by, name for display
  v_caller_id   := auth.uid();
  v_caller_name := public.get_my_full_name();

  IF p_headcount_needed < 1 OR p_headcount_needed > 50 THEN
    RAISE EXCEPTION 'headcount_needed must be 1–50, got %', p_headcount_needed;
  END IF;

  IF p_priority NOT IN ('normal', 'urgent', 'critical') THEN
    RAISE EXCEPTION 'Invalid priority: %', p_priority;
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

  SELECT account_name, group_id
  INTO v_requesting_acct_name, v_req_group_id
  FROM public.accounts
  WHERE id = p_requesting_account_id AND is_active = true;
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

  INSERT INTO public.workforce_pool_requests (
    pool_type_id, requesting_account_id, requesting_account,
    requesting_store_id, requesting_store,
    headcount_needed, priority, reason,
    status, approved_by, approved_at, created_by
  ) VALUES (
    v_pool_type_id, p_requesting_account_id, v_requesting_acct_name,
    p_requesting_store_id, v_requesting_store_name,
    p_headcount_needed, p_priority, p_reason,
    'approved', v_caller_name, now(), v_caller_id
  ) RETURNING id INTO v_pool_request_id;

  FOR i IN 1..p_headcount_needed LOOP

    v_vcode := public.generate_pool_vcode(p_pool_type_code);

    INSERT INTO public.vacancies (
      vcode, account, account_id, group_id,
      position, position_id, store_id,
      status, vacant_date, required_headcount, source,
      is_pool_vacancy, pool_type_id, home_account_id,
      affects_required_hc, affects_mfr, pool_request_id,
      created_by
    ) VALUES (
      v_vcode, v_requesting_acct_name, p_requesting_account_id, v_req_group_id,
      v_position_name, p_position_id, p_requesting_store_id,
      'Open', now(), 1, 'pool',
      true, v_pool_type_id, v_moses_hq_id,
      false, false, v_pool_request_id,
      v_caller_id
    ) RETURNING id INTO v_vacancy_id;

    INSERT INTO public.workforce_pool_slots (
      vcode, pool_type_id, vacancy_id,
      status, account, account_id, group_id, created_by
    ) VALUES (
      v_vcode, v_pool_type_id, v_vacancy_id,
      'open', v_requesting_acct_name, p_requesting_account_id,
      v_req_group_id, v_caller_id
    );

    INSERT INTO public.workforce_pool_request_items (
      request_id, vacancy_id, vcode, position_id, status
    ) VALUES (
      v_pool_request_id, v_vacancy_id, v_vcode, p_position_id, 'open'
    );

    v_created_vcodes := v_created_vcodes || v_vcode;
    v_created_ids    := v_created_ids    || v_vacancy_id;

  END LOOP;

  RETURN jsonb_build_object(
    'success',           true,
    'pool_request_id',   v_pool_request_id,
    'pool_type',         p_pool_type_code,
    'headcount_created', p_headcount_needed,
    'vcodes',            v_created_vcodes,
    'vacancy_ids',       v_created_ids
  );
END;
$function$;
