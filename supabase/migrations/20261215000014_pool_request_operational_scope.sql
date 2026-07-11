-- Migration: 20261215000014_pool_request_operational_scope.sql
-- Prompt:    ohm#poolscope004 (original) / ohm#poolscope005 (corrected)
-- Goal:      Add operational scope ownership to workforce_pool_requests so that
--            Ops pool requests count under the correct Account/Group Plantilla
--            rather than Moses HQ.  Also provides idempotent repair for
--            BUN-GHQ-00012 whose vacancy was created under the wrong account.
--
-- KEY SCHEMA FACTS (verified against base schema):
--   workforce_pool_requests.requesting_account_id → accounts(id)
--   workforce_pool_slots: columns are vcode, pool_type_id, vacancy_id, status,
--     account, account_id, group_id, is_active, created_by etc.
--     NO source_hc_request_id — that column lives only on plantilla_slots
--     (FK → headcount_requests.id). Pool requests use vacancies.pool_request_id
--     for source linkage.
--   plantilla_slots.source_hc_request_id → headcount_requests(id)
--     Never populated from workforce_pool_requests — separate HC workflow.
--   vacancies.pool_request_id → workforce_pool_requests(id)  ← pool source link
--
-- Changes:
--   §1  Schema: add 5 columns to workforce_pool_requests (split into
--       individual ALTER statements for compatibility).
--   §2  Backfill existing rows.
--   §3  Rewrite create_pool_vacancy — populate operational scope fields.
--   §4  Rewrite approve_pool_vacancy_request — same; vacancy/slot ownership
--       uses requesting_account (which Flutter now sends as the OM's account).
--   §5  repair_pool_request_slot(uuid, uuid) — idempotent, handles:
--         Case A: item count = 0 → create vacancy + slots (original)
--         Case B: items exist but vacancy under pool account (Moses HQ)
--                 and explicit p_operational_account_id provided → UPDATE
--   §6  Smoke-test queries (manual, as comments).
--
-- Invariants preserved:
--   - Moses HQ (pool account) remains home_account_id on pool vacancies.
--   - Data Team auto-approved requests stay global (is_global_pool_request=true).
--   - No hard deletes.
--   - Migration 013 RLS policy untouched.
--   - plantilla_slots is NOT written from pool request logic.

-- ─────────────────────────────────────────────────────────────────────────────
-- §1  Schema additions to workforce_pool_requests (one statement per column
--     to avoid compound-FK parsing issues in some Supabase environments)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.workforce_pool_requests
  ADD COLUMN IF NOT EXISTS operational_account_id uuid;

ALTER TABLE public.workforce_pool_requests
  ADD COLUMN IF NOT EXISTS operational_account_name text;

ALTER TABLE public.workforce_pool_requests
  ADD COLUMN IF NOT EXISTS operational_group_id uuid;

ALTER TABLE public.workforce_pool_requests
  ADD COLUMN IF NOT EXISTS operational_group_name text;

ALTER TABLE public.workforce_pool_requests
  ADD COLUMN IF NOT EXISTS is_global_pool_request boolean NOT NULL DEFAULT false;

-- FK constraints added separately so each is individually droppable if needed
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name        = 'workforce_pool_requests'
      AND constraint_name   = 'wpr_operational_account_id_fkey'
  ) THEN
    ALTER TABLE public.workforce_pool_requests
      ADD CONSTRAINT wpr_operational_account_id_fkey
      FOREIGN KEY (operational_account_id) REFERENCES public.accounts(id) ON DELETE SET NULL;
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name        = 'workforce_pool_requests'
      AND constraint_name   = 'wpr_operational_group_id_fkey'
  ) THEN
    ALTER TABLE public.workforce_pool_requests
      ADD CONSTRAINT wpr_operational_group_id_fkey
      FOREIGN KEY (operational_group_id) REFERENCES public.groups(id) ON DELETE SET NULL;
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_wpr_operational_account_id
  ON public.workforce_pool_requests (operational_account_id)
  WHERE operational_account_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- §2  Backfill existing rows
-- ─────────────────────────────────────────────────────────────────────────────

-- Data Team (auto-approved) requests → global
UPDATE public.workforce_pool_requests
SET    is_global_pool_request = true
WHERE  is_ops_request = false
  AND  is_global_pool_request = false;

-- Ops requests whose requesting_account_id is NOT the pool account → resolve
-- Old bug-data rows (requesting_account_id = Moses HQ) produce no match and
-- keep operational_account_id = NULL; repair_pool_request_slot handles those.
UPDATE public.workforce_pool_requests wpr
SET
  operational_account_id   = a.id,
  operational_account_name = a.account_name,
  operational_group_id     = a.group_id,
  operational_group_name   = g.group_name,
  is_global_pool_request   = false
FROM   public.accounts a
LEFT   JOIN public.groups g ON g.id = a.group_id
WHERE  wpr.is_ops_request         = true
  AND  wpr.operational_account_id IS NULL
  AND  a.id = wpr.requesting_account_id
  AND  COALESCE(a.is_pool_account, false) = false;

-- ─────────────────────────────────────────────────────────────────────────────
-- §3  Rewrite create_pool_vacancy
--     Pool-slot source linkage: vacancies.pool_request_id (FK to
--     workforce_pool_requests). workforce_pool_slots link via vacancy_id only.
--     plantilla_slots is NOT created here — it is HC-request territory only
--     (plantilla_slots.source_hc_request_id → headcount_requests.id).
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
      is_global_pool_request
    ) VALUES (
      v_pool_type_id, p_requesting_account_id, v_requesting_acct_name,
      p_requesting_store_id, v_requesting_store_name,
      p_headcount_needed, p_priority, p_reason,
      'pending', v_caller_id::text, v_caller_name,
      p_position_id, v_position_name, true, p_request_type,
      p_requesting_account_id, v_requesting_acct_name,
      v_req_group_id, v_req_group_name,
      false
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
    is_global_pool_request
    -- operational_account_id/name/group_id/name stay NULL for global requests
  ) VALUES (
    v_pool_type_id, p_requesting_account_id, v_requesting_acct_name,
    p_requesting_store_id, v_requesting_store_name,
    p_headcount_needed, p_priority, p_reason,
    'approved', v_caller_name, now(), v_caller_id::text, v_caller_name,
    p_position_id, v_position_name, false, p_request_type,
    true
  ) RETURNING id INTO v_pool_request_id;

  v_vcode := public.generate_pool_vcode(p_pool_type_code);

  -- Source linkage: vacancies.pool_request_id → workforce_pool_requests.id
  -- home_account_id = Moses HQ (pool source); account_id = requesting account.
  -- plantilla_slots is NOT created here (source_hc_request_id references
  -- headcount_requests.id, not workforce_pool_requests.id).
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

GRANT EXECUTE ON FUNCTION public.create_pool_vacancy(text, uuid, uuid, uuid, integer, text, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- §4  Rewrite approve_pool_vacancy_request
--     Vacancy/slot ownership uses v_req.requesting_account_id which Flutter
--     now sends as the OM's operational account for new Ops requests.
--     Old bug-data (Moses HQ as requesting_account_id) can only be fixed via
--     repair_pool_request_slot after approval.
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
  -- For requests created after this migration fix, requesting_account_id is the
  -- OM's operational account. For old bug-data it may be Moses HQ — the vacancy
  -- would be under Moses HQ and repair_pool_request_slot fixes that afterwards.
  SELECT a.group_id, g.group_name
  INTO   v_req_group_id, v_req_group_name
  FROM   public.accounts a
  LEFT   JOIN public.groups g ON g.id = a.group_id
  WHERE  a.id = v_req.requesting_account_id AND a.is_active = true;

  v_vcode := public.generate_pool_vcode(v_pool_type_code);

  -- vacancies.pool_request_id is the source link to workforce_pool_requests.
  -- home_account_id stays Moses HQ (pool source). account_id = requesting account.
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
-- §5  repair_pool_request_slot — idempotent, two-case repair
--
--   Case A (p_operational_account_id = NULL OR items = 0):
--     Items count = 0 → create missing vacancy + slots + item.
--
--   Case B (p_operational_account_id IS NOT NULL AND items > 0):
--     Items exist but the linked vacancy is under the pool account (Moses HQ).
--     → UPDATE vacancy, workforce_pool_slots, and workforce_pool_requests to
--       the specified operational account. No new vacancy/slot created.
--     → Use for BUN-GHQ-00012 after identifying the correct account.
--
--   First identify the account via:
--     SELECT a.id, a.account_name
--     FROM workforce_pool_requests wpr
--     JOIN user_scopes us ON us.user_id = (
--       SELECT id FROM users_profile WHERE id::text = wpr.created_by LIMIT 1
--     )
--     JOIN accounts a ON a.id = us.account_id AND NOT COALESCE(a.is_pool_account,false)
--     WHERE wpr.id = 'c7fb8e9c-4426-460a-a941-eceb304463a7';
--   Then call:
--     SELECT repair_pool_request_slot(
--       'c7fb8e9c-4426-460a-a941-eceb304463a7',
--       '<operational-account-uuid>'
--     );
-- ─────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.repair_pool_request_slot(uuid);
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
  -- Use when items exist but the linked vacancy was created under Moses HQ
  -- (old bug data). UPDATEs in place — no new rows created.
  IF v_item_count > 0 AND p_operational_account_id IS NOT NULL THEN
    -- Resolve the vacancy linked to this request
    SELECT v.* INTO v_vacancy
    FROM public.vacancies v
    JOIN public.workforce_pool_request_items wpri ON wpri.vacancy_id = v.id
    WHERE wpri.request_id = p_request_id
    LIMIT 1;

    IF v_vacancy.id IS NULL THEN
      RAISE EXCEPTION 'BUG: items exist but no linked vacancy found for request %', p_request_id;
    END IF;

    -- Only repair if the vacancy is currently under the pool (Moses HQ) account.
    -- If it's already under a non-pool account, skip to avoid overwriting.
    IF COALESCE(v_vacancy.account_id = v_moses_hq_id, false) = false THEN
      RETURN jsonb_build_object(
        'success',          true,
        'already_repaired', true,
        'vacancy_id',       v_vacancy.id,
        'vacancy_account',  v_vacancy.account,
        'message',          'Vacancy is already under a non-pool account — no repair needed.'
      );
    END IF;

    -- Resolve the operational account details
    SELECT a.account_name, a.group_id, g.group_name
    INTO   v_op_account_name, v_op_group_id, v_op_group_name
    FROM   public.accounts a
    LEFT   JOIN public.groups g ON g.id = a.group_id
    WHERE  a.id = p_operational_account_id AND a.is_active = true
      AND  COALESCE(a.is_pool_account, false) = false;
    IF v_op_account_name IS NULL THEN
      RAISE EXCEPTION 'Operational account not found, inactive, or is the pool account: %', p_operational_account_id;
    END IF;

    -- UPDATE vacancy ownership
    UPDATE public.vacancies
    SET account    = v_op_account_name,
        account_id = p_operational_account_id,
        group_id   = v_op_group_id,
        updated_at = now()
    WHERE id = v_vacancy.id;

    -- UPDATE workforce_pool_slots linked to this vacancy
    UPDATE public.workforce_pool_slots
    SET account    = v_op_account_name,
        account_id = p_operational_account_id,
        group_id   = v_op_group_id,
        updated_at = now(),
        updated_by = v_caller_id::text
    WHERE vacancy_id = v_vacancy.id
      AND deleted_at IS NULL;
    GET DIAGNOSTICS v_slots_updated = ROW_COUNT;

    -- UPDATE workforce_pool_requests operational scope fields
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

  -- Use explicit operational account if provided, else requesting_account_id
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
    created_by, is_ops_request
  ) VALUES (
    v_vcode,
    v_op_account_name, v_op_account_id, v_op_group_id,
    v_req.position_name, v_req.position_id, v_req.requesting_store_id,
    'Open', now(), v_req.headcount_needed, 'pool',
    true, v_req.pool_type_id, v_moses_hq_id,
    false, false, v_req.id,
    COALESCE(v_req.created_by::uuid, v_caller_id), true
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

-- ─────────────────────────────────────────────────────────────────────────────
-- §6  Smoke-test queries (run manually in order — comments only)
-- ─────────────────────────────────────────────────────────────────────────────

-- [1] Verify schema columns were added (expect 5 rows):
--   SELECT column_name, data_type, is_nullable, column_default
--   FROM information_schema.columns
--   WHERE table_schema = 'public'
--     AND table_name   = 'workforce_pool_requests'
--     AND column_name IN (
--       'operational_account_id','operational_account_name',
--       'operational_group_id','operational_group_name','is_global_pool_request'
--     )
--   ORDER BY column_name;

-- [2] Verify FK constraints exist (expect 2 rows):
--   SELECT constraint_name, constraint_type
--   FROM information_schema.table_constraints
--   WHERE table_schema = 'public'
--     AND table_name   = 'workforce_pool_requests'
--     AND constraint_name IN (
--       'wpr_operational_account_id_fkey','wpr_operational_group_id_fkey'
--     );

-- [3] Backfill check — no Data Team request should be non-global (expect 0):
--   SELECT COUNT(*) FROM public.workforce_pool_requests
--   WHERE is_ops_request = false AND is_global_pool_request = false;

-- [4] Backfill check — Ops requests with resolvable non-pool account (expect 0):
--   SELECT COUNT(*) FROM public.workforce_pool_requests wpr
--   JOIN public.accounts a ON a.id = wpr.requesting_account_id
--   WHERE wpr.is_ops_request = true
--     AND COALESCE(a.is_pool_account, false) = false
--     AND wpr.operational_account_id IS NULL;

-- [5a] BUN-GHQ-00012 DIAGNOSTIC — identify the owner's operational account:
--   SELECT DISTINCT
--     us.account_id,
--     a.account_name,
--     a.group_id,
--     g.group_name
--   FROM public.workforce_pool_requests wpr
--   JOIN public.users_profile up ON up.id::text = wpr.created_by
--   JOIN public.user_scopes   us ON us.user_id = up.id
--   JOIN public.accounts      a  ON a.id = us.account_id
--     AND COALESCE(a.is_pool_account, false) = false
--   LEFT JOIN public.groups   g  ON g.id = a.group_id
--   WHERE wpr.id = 'c7fb8e9c-4426-460a-a941-eceb304463a7';
--   → Note the account_id from results.

-- [5b] BUN-GHQ-00012 REPAIR — substitute the account_id from [5a]:
--   SELECT public.repair_pool_request_slot(
--     'c7fb8e9c-4426-460a-a941-eceb304463a7'::uuid,
--     '<operational-account-uuid-from-5a>'::uuid
--   );
--   → Expected: {"success":true,"repaired":true,"repair_type":"account_corrected",
--                "vcode":"BUN-GHQ-00012","new_account":"<TWO or correct name>",
--                "slots_updated":N,...}

-- [5c] Verify BUN-GHQ-00012 vacancy is no longer under Moses HQ:
--   SELECT v.id, v.vcode, v.account, v.account_id, v.home_account_id
--   FROM public.vacancies v
--   WHERE v.id = 'cb9626aa-1f37-4f59-957f-f31aca1fc5de';
--   → account_id should now be the operational account, NOT Moses HQ.
--   → home_account_id should still be Moses HQ.

-- [5d] Verify workforce_pool_slots updated:
--   SELECT wps.id, wps.vcode, wps.account, wps.account_id
--   FROM public.workforce_pool_slots wps
--   WHERE wps.vacancy_id = 'cb9626aa-1f37-4f59-957f-f31aca1fc5de'
--     AND wps.deleted_at IS NULL;
--   → account_id should match the operational account.

-- [5e] Verify operational_account_id populated on the request:
--   SELECT id, operational_account_id, operational_account_name, is_global_pool_request
--   FROM public.workforce_pool_requests
--   WHERE id = 'c7fb8e9c-4426-460a-a941-eceb304463a7';
--   → operational_account_id NOT NULL, is_global_pool_request = false.

-- [6] Verify workforce_pool_slots still uses vacancy_id for source linkage
--     (no source_hc_request_id on this table — that column is plantilla_slots only):
--   SELECT column_name
--   FROM information_schema.columns
--   WHERE table_schema = 'public'
--     AND table_name   = 'workforce_pool_slots'
--     AND column_name  = 'source_hc_request_id';
--   → Expected: 0 rows (correct — source_hc_request_id lives only on plantilla_slots
--     where it references headcount_requests.id, not workforce_pool_requests).
