-- Migration: 20261215000009_one_vcode_per_pool_request.sql
-- Goal: Enforce 1 Workforce Request = 1 VCode architecture
--
-- Fixes:
-- 1. generate_pool_vcode: hardcoded '-GHQ-' suffix doubled the prefix
--    (BUN-GHQ prefix + '-GHQ-' + seq = BUN-GHQ-GHQ-00001). Changed to '-'.
-- 2. create_pool_vacancy (Data Team path): was looping p_headcount_needed times,
--    creating one vacancy per HC unit. Now creates exactly one VCode + one vacancy
--    (required_headcount = p_headcount_needed) + p_headcount_needed slot rows +
--    one request item per request.
-- 3. approve_pool_vacancy_request: same loop-per-HC bug. Fixed identically.
--
-- Historical VCodes with the old format (BUN-GHQ-GHQ-00001 etc.) are preserved.
-- Sequences continue from their current last_val — no backfill required.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Fix generate_pool_vcode (remove hardcoded '-GHQ-', use '-' only)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.generate_pool_vcode(p_pool_type_code text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_prefix   text;
  v_next_val bigint;
  v_vcode    text;
BEGIN
  SELECT vcode_prefix INTO v_prefix
  FROM public.workforce_pool_types
  WHERE code = p_pool_type_code AND is_active = true;

  IF v_prefix IS NULL THEN
    RAISE EXCEPTION 'Invalid or inactive pool type code: %', p_pool_type_code;
  END IF;

  INSERT INTO public.workforce_pool_vcode_sequences (prefix, last_val)
  VALUES (v_prefix, 1)
  ON CONFLICT (prefix)
  DO UPDATE SET last_val = public.workforce_pool_vcode_sequences.last_val + 1
  RETURNING last_val INTO v_next_val;

  -- Use single separator '-' so BUN-GHQ prefix yields BUN-GHQ-00001 (not BUN-GHQ-GHQ-00001)
  v_vcode := v_prefix || '-' || LPAD(v_next_val::text, 5, '0');

  IF EXISTS (SELECT 1 FROM public.vacancies WHERE vcode = v_vcode) THEN
    RAISE EXCEPTION 'VCODE collision detected: %. Contact SA.', v_vcode;
  END IF;

  RETURN v_vcode;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Rewrite create_pool_vacancy: 1 VCode per request (not per HC unit)
--    Keeps the same function signature from migration 007.
-- ─────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.create_pool_vacancy(text, uuid, uuid, uuid, integer, text, text, text);

CREATE OR REPLACE FUNCTION public.create_pool_vacancy(
  p_pool_type_code        text,
  p_position_id           uuid,
  p_requesting_account_id uuid,
  p_requesting_store_id   uuid    DEFAULT NULL::uuid,
  p_headcount_needed      integer DEFAULT 1,
  p_priority              text    DEFAULT 'normal'::text,
  p_reason                text    DEFAULT NULL::text,
  p_request_type          text    DEFAULT 'Additional'::text
)
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
  v_caller_id   := auth.uid();
  v_caller_name := public.get_my_full_name();

  IF p_headcount_needed < 1 OR p_headcount_needed > 50 THEN
    RAISE EXCEPTION 'headcount_needed must be 1–50, got %', p_headcount_needed;
  END IF;

  IF p_priority NOT IN ('normal', 'urgent', 'critical') THEN
    RAISE EXCEPTION 'Invalid priority: %', p_priority;
  END IF;

  IF p_request_type NOT IN ('Additional', 'Replacement') THEN
    RAISE EXCEPTION 'Invalid request_type: %. Must be Additional or Replacement', p_request_type;
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

  -- ── Ops path: create pending request only (no vacancy yet) ──────────────
  IF v_is_ops_request THEN
    INSERT INTO public.workforce_pool_requests (
      pool_type_id, requesting_account_id, requesting_account,
      requesting_store_id, requesting_store,
      headcount_needed, priority, reason,
      status, created_by, created_by_name,
      position_id, position_name, is_ops_request, request_type
    ) VALUES (
      v_pool_type_id, p_requesting_account_id, v_requesting_acct_name,
      p_requesting_store_id, v_requesting_store_name,
      p_headcount_needed, p_priority, p_reason,
      'pending', v_caller_id::text, v_caller_name,
      p_position_id, v_position_name, true, p_request_type
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

  -- ── Data Team path: auto-approved, 1 VCode + 1 vacancy + N slots + 1 item ──
  INSERT INTO public.workforce_pool_requests (
    pool_type_id, requesting_account_id, requesting_account,
    requesting_store_id, requesting_store,
    headcount_needed, priority, reason,
    status, approved_by, approved_at, created_by, created_by_name,
    position_id, position_name, is_ops_request, request_type
  ) VALUES (
    v_pool_type_id, p_requesting_account_id, v_requesting_acct_name,
    p_requesting_store_id, v_requesting_store_name,
    p_headcount_needed, p_priority, p_reason,
    'approved', v_caller_name, now(), v_caller_id::text, v_caller_name,
    p_position_id, v_position_name, false, p_request_type
  ) RETURNING id INTO v_pool_request_id;

  -- One VCode for the entire request
  v_vcode := public.generate_pool_vcode(p_pool_type_code);

  -- One vacancy row with required_headcount = total HC requested
  INSERT INTO public.vacancies (
    vcode, account, account_id, group_id,
    position, position_id, store_id,
    status, vacant_date, required_headcount, source,
    is_pool_vacancy, pool_type_id, home_account_id,
    affects_required_hc, affects_mfr, pool_request_id,
    created_by, is_ops_request
  ) VALUES (
    v_vcode, v_requesting_acct_name, p_requesting_account_id, v_req_group_id,
    v_position_name, p_position_id, p_requesting_store_id,
    'Open', now(), p_headcount_needed, 'pool',
    true, v_pool_type_id, v_moses_hq_id,
    false, false, v_pool_request_id,
    v_caller_id, false
  ) RETURNING id INTO v_vacancy_id;

  -- N slot rows (one per HC capacity unit) all under the same VCode/vacancy
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

  -- One request item referencing the single VCode
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

GRANT EXECUTE ON FUNCTION public.create_pool_vacancy(text, uuid, uuid, uuid, integer, text, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Rewrite approve_pool_vacancy_request: 1 VCode per approved request
-- ─────────────────────────────────────────────────────────────────────────────
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
  i                int;
BEGIN
  v_role_level := public.get_my_role_level();
  IF v_role_level IS NULL OR v_role_level NOT IN (100, 90, 30) THEN
    RAISE EXCEPTION 'Unauthorized: approve_pool_vacancy_request requires Data Team/Admin access (SA/HA/Encoder)';
  END IF;

  v_caller_id   := auth.uid();
  v_caller_name := public.get_my_full_name();

  SELECT * INTO v_req
  FROM public.workforce_pool_requests
  WHERE id = p_request_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'Request is already processed: status is %', v_req.status;
  END IF;

  SELECT code INTO v_pool_type_code
  FROM public.workforce_pool_types
  WHERE id = v_req.pool_type_id;

  SELECT id INTO v_moses_hq_id
  FROM public.accounts
  WHERE is_pool_account = true AND is_active = true
  LIMIT 1;

  SELECT group_id INTO v_req_group_id
  FROM public.accounts
  WHERE id = v_req.requesting_account_id AND is_active = true;

  -- One VCode for the entire approved request
  v_vcode := public.generate_pool_vcode(v_pool_type_code);

  -- One vacancy row with required_headcount = total HC approved
  INSERT INTO public.vacancies (
    vcode, account, account_id, group_id,
    position, position_id, store_id,
    status, vacant_date, required_headcount, source,
    is_pool_vacancy, pool_type_id, home_account_id,
    affects_required_hc, affects_mfr, pool_request_id,
    created_by, is_ops_request
  ) VALUES (
    v_vcode, v_req.requesting_account, v_req.requesting_account_id, v_req_group_id,
    v_req.position_name, v_req.position_id, v_req.requesting_store_id,
    'Open', now(), v_req.headcount_needed, 'pool',
    true, v_req.pool_type_id, v_moses_hq_id,
    false, false, v_req.id,
    v_req.created_by::uuid, true
  ) RETURNING id INTO v_vacancy_id;

  -- N slot rows (one per HC capacity unit) all under the same VCode/vacancy
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

  -- One request item referencing the single VCode
  INSERT INTO public.workforce_pool_request_items (
    request_id, vacancy_id, vcode, position_id, status
  ) VALUES (
    v_req.id, v_vacancy_id, v_vcode, v_req.position_id, 'open'
  );

  UPDATE public.workforce_pool_requests
  SET status = 'approved',
      approved_by = v_caller_name,
      approved_at = now(),
      updated_by = v_caller_id::text,
      updated_at = now()
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

GRANT EXECUTE ON FUNCTION public.approve_pool_vacancy_request(uuid) TO authenticated;
