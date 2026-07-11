-- Migration: 20261215000007_workforce_pool_positions_and_request_type.sql
-- Goal: Make MOSES HQ HC Request Position DB-driven and add Request Type

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Extend positions table with pool position markers
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.positions
  ADD COLUMN IF NOT EXISTS is_pool_position boolean DEFAULT false NOT NULL,
  ADD COLUMN IF NOT EXISTS pool_sort_order int;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Seed / mark the three canonical pool positions
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_id uuid;
BEGIN
  -- Commando
  SELECT id INTO v_id FROM public.positions
    WHERE LOWER(TRIM(position_name)) = 'commando' LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO public.positions (position_name, is_active, is_pool_position, pool_sort_order)
    VALUES ('Commando', true, true, 1);
  ELSE
    UPDATE public.positions
       SET is_pool_position = true, pool_sort_order = 1
     WHERE id = v_id;
  END IF;

  -- Reliever
  SELECT id INTO v_id FROM public.positions
    WHERE LOWER(TRIM(position_name)) = 'reliever' LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO public.positions (position_name, is_active, is_pool_position, pool_sort_order)
    VALUES ('Reliever', true, true, 2);
  ELSE
    UPDATE public.positions
       SET is_pool_position = true, pool_sort_order = 2
     WHERE id = v_id;
  END IF;

  -- Seasonal
  SELECT id INTO v_id FROM public.positions
    WHERE LOWER(TRIM(position_name)) = 'seasonal' LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO public.positions (position_name, is_active, is_pool_position, pool_sort_order)
    VALUES ('Seasonal', true, true, 3);
  ELSE
    UPDATE public.positions
       SET is_pool_position = true, pool_sort_order = 3
     WHERE id = v_id;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Add request_type column to workforce_pool_requests
--    Existing rows default to 'Additional'
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.workforce_pool_requests
  ADD COLUMN IF NOT EXISTS request_type text DEFAULT 'Additional' NOT NULL;

ALTER TABLE public.workforce_pool_requests
  DROP CONSTRAINT IF EXISTS workforce_pool_requests_request_type_check;

ALTER TABLE public.workforce_pool_requests
  ADD CONSTRAINT workforce_pool_requests_request_type_check
    CHECK (request_type IN ('Additional', 'Replacement'));

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Replace create_pool_vacancy with a version that persists request_type
-- ─────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.create_pool_vacancy(text, uuid, uuid, uuid, integer, text, text);

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
  v_created_vcodes        text[] := '{}';
  v_created_ids           uuid[] := '{}';
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
      'vcodes',            v_created_vcodes,
      'vacancy_ids',       v_created_ids
    );
  ELSE
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

    FOR i IN 1..p_headcount_needed LOOP
      v_vcode := public.generate_pool_vcode(p_pool_type_code);

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
        'Open', now(), 1, 'pool',
        true, v_pool_type_id, v_moses_hq_id,
        false, false, v_pool_request_id,
        v_caller_id, false
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
      'vacancy_created',   true,
      'vcodes',            v_created_vcodes,
      'vacancy_ids',       v_created_ids
    );
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.create_pool_vacancy(text, uuid, uuid, uuid, integer, text, text, text) TO authenticated;
