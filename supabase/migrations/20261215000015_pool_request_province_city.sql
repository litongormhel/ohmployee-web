-- Migration: 20261215000015_pool_request_province_city.sql
-- Prompt:    ohm#poolscope008
-- Goal:      Persist Province/City selected in the HC Request form on
--            workforce_pool_requests and their generated vacancies, so that
--            pool vacancy cards display the OM-selected location instead of
--            a fallback account name.
--
-- Business Rule:
--   - Province / City label on vacancy cards must NEVER be the account name.
--   - The value must be the province/city the OM selected in the form.
--   - Data Team global pool vacancies have no province/city → display '—' or
--     'Global Pool' (handled client-side).
--
-- Changes:
--   §1  Add requested_province, requested_city to workforce_pool_requests.
--   §2  Rewrite create_pool_vacancy — new signature (10 params) accepts
--       p_province, p_city; persists on request row and vacancy.
--   §3  Rewrite approve_pool_vacancy_request — passes v_req.requested_province
--       and v_req.requested_city to the generated vacancy row.
--   §4  Update repair_pool_request_slot — vacancy INSERT includes province/city
--       from request (null for old data with no stored province/city).
--
-- Invariants preserved:
--   - VCode generation unchanged.
--   - RLS policies unchanged.
--   - home_account_id = Moses HQ on all pool vacancies (unchanged).
--   - No hard deletes.
--   - plantilla_slots is NOT created from pool request logic (unchanged).
--   - Old pool requests/vacancies retain NULL province/city (no backfill;
--     province/city cannot be inferred from historical data).

-- ─────────────────────────────────────────────────────────────────────────────
-- §1  Schema additions to workforce_pool_requests
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.workforce_pool_requests
  ADD COLUMN IF NOT EXISTS requested_province text;

ALTER TABLE public.workforce_pool_requests
  ADD COLUMN IF NOT EXISTS requested_city text;

-- ─────────────────────────────────────────────────────────────────────────────
-- §2  Rewrite create_pool_vacancy
--     New params: p_province text DEFAULT NULL, p_city text DEFAULT NULL
--     Old 8-param signature must be dropped first.
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
  p_request_type          text    DEFAULT 'Additional'::text,
  p_province              text    DEFAULT NULL::text,
  p_city                  text    DEFAULT NULL::text
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

  -- ── Data Team path: auto-approved — 1 VCode + 1 vacancy + N slots + 1 item
  INSERT INTO public.workforce_pool_requests (
    pool_type_id, requesting_account_id, requesting_account,
    requesting_store_id, requesting_store,
    headcount_needed, priority, reason,
    status, approved_by, approved_at, created_by, created_by_name,
    position_id, position_name, is_ops_request, request_type,
    is_global_pool_request,
    requested_province, requested_city
    -- operational_account_id/name/group_id/name stay NULL for global requests
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

  -- Source linkage: vacancies.pool_request_id → workforce_pool_requests.id
  -- home_account_id = Moses HQ (pool source); account_id = requesting account.
  -- province/area_city are populated from the form selection so the vacancy
  -- card displays the chosen location rather than a fallback account name.
  -- plantilla_slots is NOT created here.
  INSERT INTO public.vacancies (
    vcode, account, account_id, group_id,
    position, position_id, store_id,
    status, vacant_date, required_headcount, source,
    is_pool_vacancy, pool_type_id, home_account_id,
    affects_required_hc, affects_mfr, pool_request_id,
    created_by, is_ops_request,
    province, area_city
  ) VALUES (
    v_vcode, v_requesting_acct_name, p_requesting_account_id, v_req_group_id,
    v_position_name, p_position_id, p_requesting_store_id,
    'Open', now(), p_headcount_needed, 'pool',
    true, v_pool_type_id, v_moses_hq_id,
    false, false, v_pool_request_id,
    v_caller_id, false,
    p_province, p_city
  ) RETURNING id INTO v_vacancy_id;

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

GRANT EXECUTE ON FUNCTION public.create_pool_vacancy(text, uuid, uuid, uuid, integer, text, text, text, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- §3  Rewrite approve_pool_vacancy_request
--     Reads requested_province/city from the pool request row and writes
--     them to the generated vacancy.
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

  -- province/area_city come from the original request so the vacancy card
  -- displays the province/city the OM selected, not a fallback account name.
  INSERT INTO public.vacancies (
    vcode, account, account_id, group_id,
    position, position_id, store_id,
    status, vacant_date, required_headcount, source,
    is_pool_vacancy, pool_type_id, home_account_id,
    affects_required_hc, affects_mfr, pool_request_id,
    created_by, is_ops_request,
    province, area_city
  ) VALUES (
    v_vcode, v_req.requesting_account, v_req.requesting_account_id, v_req_group_id,
    v_req.position_name, v_req.position_id, v_req.requesting_store_id,
    'Open', now(), v_req.headcount_needed, 'pool',
    true, v_req.pool_type_id, v_moses_hq_id,
    false, false, v_req.id,
    v_req.created_by::uuid, true,
    v_req.requested_province, v_req.requested_city
  ) RETURNING id INTO v_vacancy_id;

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

GRANT EXECUTE ON FUNCTION public.approve_pool_vacancy_request(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- §4  Update repair_pool_request_slot (Case A vacancy INSERT)
--     Includes province/city from request row — null for pre-migration data.
-- ─────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.repair_pool_request_slot(uuid, uuid);

CREATE OR REPLACE FUNCTION public.repair_pool_request_slot(
  p_request_id             uuid,
  p_operational_account_id uuid DEFAULT NULL::uuid
)
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

  -- province/city from request (NULL for pre-migration requests — acceptable,
  -- since province/city cannot be inferred from historical data).
  INSERT INTO public.vacancies (
    vcode, account, account_id, group_id,
    position, position_id, store_id,
    status, vacant_date, required_headcount, source,
    is_pool_vacancy, pool_type_id, home_account_id,
    affects_required_hc, affects_mfr, pool_request_id,
    created_by, is_ops_request,
    province, area_city
  ) VALUES (
    v_vcode,
    v_op_account_name, v_op_account_id, v_op_group_id,
    v_req.position_name, v_req.position_id, v_req.requesting_store_id,
    'Open', now(), v_req.headcount_needed, 'pool',
    true, v_req.pool_type_id, v_moses_hq_id,
    false, false, v_req.id,
    COALESCE(v_req.created_by::uuid, v_caller_id), true,
    v_req.requested_province, v_req.requested_city
  ) RETURNING id INTO v_vacancy_id;

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

GRANT EXECUTE ON FUNCTION public.repair_pool_request_slot(uuid, uuid) TO authenticated;

-- Reload PostgREST schema cache so the new 10-param signature is immediately
-- visible to callers without a manual server restart.
NOTIFY pgrst, 'reload schema';

-- ─────────────────────────────────────────────────────────────────────────────
-- Smoke-test queries (manual, run after migration apply)
-- ─────────────────────────────────────────────────────────────────────────────

-- [1] Verify new columns exist (expect 2 rows):
--   SELECT column_name, data_type
--   FROM information_schema.columns
--   WHERE table_schema = 'public'
--     AND table_name   = 'workforce_pool_requests'
--     AND column_name IN ('requested_province', 'requested_city')
--   ORDER BY column_name;

-- [2] Verify create_pool_vacancy signature updated (expect 10 params):
--   SELECT pg_get_function_identity_arguments('create_pool_vacancy'::regproc);
--   → should include p_province text, p_city text at the end

-- [3] After creating a new Ops pool request with province/city:
--   SELECT id, requested_province, requested_city
--   FROM workforce_pool_requests
--   ORDER BY created_at DESC LIMIT 1;
--   → requested_province and requested_city should be non-null.

-- [4] After approving the request:
--   SELECT v.vcode, v.province, v.area_city
--   FROM vacancies v
--   JOIN workforce_pool_requests wpr ON wpr.id = v.pool_request_id
--   ORDER BY v.created_at DESC LIMIT 1;
--   → province and area_city should match the selected values.

-- [5] Old requests: province/city remain NULL — no backfill (historical data
--     cannot be inferred). Vacancy card shows '—' for old Ops pool vacancies.
--   SELECT COUNT(*) FROM workforce_pool_requests
--   WHERE is_ops_request = true AND requested_province IS NULL;
--   → Non-zero expected (pre-migration requests). This is correct.
