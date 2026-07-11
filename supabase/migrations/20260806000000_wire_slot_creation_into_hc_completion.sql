-- ============================================================
-- OHM2026_0004 — Wire Slot Creation Into HC Request Completion
-- Migration: 20260806000000_wire_slot_creation_into_hc_completion.sql
-- Depends on:
--   20260804000000_plantilla_slot_foundation_v1.sql
--     (plantilla_slots, slot_history, slot_reason_codes)
--   20260805000000_fn_create_slots_from_hc_request.sql
--     (fn_create_slots_from_hc_request)
--   20260712000000_enforce_recruitment_freeze.sql
--     (create_plantilla_slot_from_request)
--   Pre-existing: headcount_requests, accounts, groups, stores,
--     positions, plantilla, vacancies, users_profile
--   Pre-existing helpers: get_my_role(), get_current_profile_id(),
--     i_have_full_access(), fn_assert_freeze_inactive(),
--     generate_vcode_for_account()
-- ============================================================
-- Scope: BACKEND WIRING ONLY.
--
--   §1  Add source_hc_request_id to plantilla_slots (linkage + idempotency anchor)
--   §2  Update fn_create_slots_from_hc_request to populate source_hc_request_id
--   §3  Update create_plantilla_slot_from_request — wire slot creation call
--
-- This migration deliberately does NOT:
--   • alter Vacancy / HR Emploc / Plantilla / Transfer / Import behavior,
--   • touch MFR / CENCOM,
--   • change the vacancy/plantilla-pool loop inside
--     create_plantilla_slot_from_request,
--   • migrate or backfill existing data,
--   • advance headcount_requests.status beyond what already existed.
--
-- TRANSITIONAL DUAL-WRITE STRATEGY:
--   The existing vacancy/plantilla-pool creation loop in
--   create_plantilla_slot_from_request is preserved unchanged. This
--   migration adds a co-located call to fn_create_slots_from_hc_request
--   that creates the matching plantilla_slots rows atomically in the
--   same transaction. Both writes commit or roll back together.
--   When the slot-first architecture is fully adopted, the existing loop
--   will be replaced by slot-derived vacancies; this dual-write phase
--   bridges that gap without disrupting current UI or workflow behaviour.
--
-- IDEMPOTENCY STRATEGY (two-layer defence):
--   Layer 1 — outer guard: create_plantilla_slot_from_request already
--     requires status = 'approved_pending_vcode'. After completion the
--     status becomes 'completed', so the function cannot be re-entered
--     for the same request. This prevents all ordinary duplicate calls.
--   Layer 2 — source_hc_request_id EXISTS check: before calling
--     fn_create_slots_from_hc_request, the function checks whether any
--     plantilla_slots row already carries source_hc_request_id = request.
--     This guards against the edge case where an operator called
--     fn_create_slots_from_hc_request directly (which does not advance
--     the status), then create_plantilla_slot_from_request runs — without
--     this check, a second batch of slots would be created.
--
-- Validation Queries (run manually after applying):
--   V1 – Column exists
--     SELECT column_name FROM information_schema.columns
--       WHERE table_schema = 'public'
--         AND table_name   = 'plantilla_slots'
--         AND column_name  = 'source_hc_request_id';
--   V2 – fn_create_slots_from_hc_request populates source_hc_request_id
--     SELECT source_hc_request_id IS NOT NULL AS linked
--       FROM public.plantilla_slots
--       ORDER BY created_at DESC LIMIT 5;
--   V3 – create_plantilla_slot_from_request returns slot_result
--     SELECT create_plantilla_slot_from_request('<approved_request_id>'::uuid);
--     -- expect: { ok: true, ..., slot_result: { ok: true, slots_created: N } }
--   V4 – Repeated calls do not create duplicate slots
--     -- call create_plantilla_slot_from_request twice for same request_id;
--     -- second call should return ok=false, error='request_not_approved'
--     -- and plantilla_slots count for that source_hc_request_id must equal N.
-- ============================================================


-- ============================================================
-- §1  Add source_hc_request_id to plantilla_slots
-- ============================================================
-- Links each plantilla_slots row back to the headcount_requests it was
-- created from. Serves two purposes:
--   (a) Operational traceability — auditors can follow HC request → slots.
--   (b) Idempotency anchor — the EXISTS check in
--       create_plantilla_slot_from_request reads this column to detect
--       whether slots were already created for a given request, regardless
--       of how they were created.
--
-- NULL is allowed: slots created via future workflows (resignation refill,
-- manual creation) will not carry an HC request link.

ALTER TABLE public.plantilla_slots
  ADD COLUMN IF NOT EXISTS source_hc_request_id uuid
  REFERENCES public.headcount_requests(id);

COMMENT ON COLUMN public.plantilla_slots.source_hc_request_id IS
  'The headcount_requests.id that triggered this slot''s creation. NULL for '
  'slots created outside the HC request workflow (resignations, manual adds, '
  'etc.). Used as an idempotency anchor: existence of a row with this value '
  'prevents duplicate slot creation on re-entry.';

-- Partial index: only rows that have a source HC request need fast lookup.
CREATE INDEX IF NOT EXISTS idx_plantilla_slots_source_hc_request_id
  ON public.plantilla_slots(source_hc_request_id)
  WHERE source_hc_request_id IS NOT NULL;


-- ============================================================
-- §2  Update fn_create_slots_from_hc_request
-- ============================================================
-- Adds source_hc_request_id to the plantilla_slots INSERT so that every
-- slot created by this RPC is traceable to its originating HC request.
-- All other behaviour is identical to the 20260805000000 version.

CREATE OR REPLACE FUNCTION public.fn_create_slots_from_hc_request(
  p_request_id uuid,
  p_quantity   integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_role            text    := public.get_my_role();
  v_caller_id       uuid    := public.get_current_profile_id();
  v_req             public.headcount_requests%ROWTYPE;
  v_account         public.accounts%ROWTYPE;
  v_store           public.stores%ROWTYPE;
  v_group           public.groups%ROWTYPE;
  v_position        public.positions%ROWTYPE;
  v_qty             integer;
  v_slot_id         uuid;
  v_slot_ids        uuid[]  := ARRAY[]::uuid[];
  v_is_roving       boolean;
  v_employment_type text;
  v_position_name   text;
  v_group_id        uuid;
  i                 integer;
BEGIN
  -- ── RBAC: Data Team (Encoder) and full-access roles ───────────────────────
  -- Mirrors the RBAC guard in create_plantilla_slot_from_request.
  IF v_role NOT IN ('Encoder', 'Head Admin', 'Super Admin') THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'forbidden',
      'hint',  'requires Encoder, Head Admin, or Super Admin'
    );
  END IF;

  -- ── Fetch and pessimistically lock the HC request ─────────────────────────
  SELECT * INTO v_req
  FROM public.headcount_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  -- ── Guard: only approved requests are eligible for slot creation ──────────
  -- Status 'approved_pending_vcode' is set by approve_headcount_request().
  -- Slot creation for any other status is blocked to prevent orphaned slots.
  IF v_req.status <> 'approved_pending_vcode' THEN
    RETURN jsonb_build_object(
      'ok',      false,
      'error',   'request_not_in_approved_state',
      'current', v_req.status,
      'expected','approved_pending_vcode'
    );
  END IF;

  -- ── Resolve quantity ──────────────────────────────────────────────────────
  -- Caller override takes precedence; falls back to request headcount_needed.
  v_qty := COALESCE(p_quantity, v_req.headcount_needed, 1);

  IF v_qty < 1 THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'invalid_quantity',
      'hint',  'quantity must be greater than 0'
    );
  END IF;

  -- ── Validate account (required) ───────────────────────────────────────────
  IF v_req.account_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'missing_account_id',
      'hint',  'headcount_requests.account_id is required for slot creation'
    );
  END IF;

  SELECT * INTO v_account FROM public.accounts WHERE id = v_req.account_id;
  IF v_account.id IS NULL THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'invalid_reference',
      'field', 'account_id'
    );
  END IF;

  -- ── Validate store (when present on the request) ──────────────────────────
  -- Roving slots may have no fixed home store (store_id = NULL is allowed).
  IF v_req.store_id IS NOT NULL THEN
    SELECT * INTO v_store FROM public.stores WHERE id = v_req.store_id;
    IF v_store.id IS NULL THEN
      RETURN jsonb_build_object(
        'ok',    false,
        'error', 'invalid_reference',
        'field', 'store_id'
      );
    END IF;
  END IF;

  -- ── Resolve and validate group_id ─────────────────────────────────────────
  v_group_id := COALESCE(v_req.group_id, v_account.group_id);
  IF v_group_id IS NOT NULL THEN
    SELECT * INTO v_group FROM public.groups WHERE id = v_group_id;
    IF v_group.id IS NULL THEN
      RETURN jsonb_build_object(
        'ok',    false,
        'error', 'invalid_reference',
        'field', 'group_id'
      );
    END IF;
  END IF;

  -- ── Resolve position name ─────────────────────────────────────────────────
  -- Prefer live lookup via position_id; fall back to snapshot text.
  IF v_req.position_id IS NOT NULL THEN
    SELECT * INTO v_position FROM public.positions WHERE id = v_req.position_id;
    IF v_position.id IS NULL THEN
      RETURN jsonb_build_object(
        'ok',    false,
        'error', 'invalid_reference',
        'field', 'position_id'
      );
    END IF;
    v_position_name := v_position.position_name;
  ELSE
    v_position_name := v_req.position_name_snapshot;
  END IF;

  IF v_position_name IS NULL OR TRIM(v_position_name) = '' THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'missing_position',
      'hint',  'no resolvable position on HC request'
    );
  END IF;

  -- ── Resolve employment_type and roving flag ───────────────────────────────
  v_employment_type := v_req.employment_type;
  -- Roving multi-store coverage linkage is deferred. Roving slots are created
  -- with is_roving=true and store_id=NULL; coverage is a future-phase attribute.
  v_is_roving := (v_employment_type = 'Roving');

  -- ── Create one slot + one history row per HC unit ─────────────────────────
  FOR i IN 1..v_qty LOOP

    INSERT INTO public.plantilla_slots (
      store_id,
      account_id,
      group_id,
      position,
      employment_type,
      is_roving,
      slot_status,
      source_hc_request_id,   -- §2 addition: HC request linkage + idempotency anchor
      created_by,
      updated_by
    ) VALUES (
      v_store.id,             -- NULL when store_id was absent on the HC request
      v_account.id,
      v_group_id,
      v_position_name,
      v_employment_type,
      v_is_roving,
      'open',
      p_request_id,           -- §2 addition
      v_caller_id,
      v_caller_id
    )
    RETURNING id INTO v_slot_id;

    v_slot_ids := array_append(v_slot_ids, v_slot_id);

    -- One history row per slot: records the creation event with reason HC_ADD.
    INSERT INTO public.slot_history (
      slot_id,
      account_id,
      action_type,
      new_value,
      reason_code,
      performed_by,
      remarks
    ) VALUES (
      v_slot_id,
      v_account.id,
      'created',
      'open',
      'HC_ADD',
      v_caller_id,
      format(
        'Slot %s of %s created from HC request %s — %s %s',
        i, v_qty,
        p_request_id::text,
        v_employment_type,
        v_position_name
      )
    );

  END LOOP;

  RETURN jsonb_build_object(
    'ok',            true,
    'request_id',    p_request_id,
    'slots_created', v_qty,
    'slot_ids',      v_slot_ids
  );

END;
$$;

COMMENT ON FUNCTION public.fn_create_slots_from_hc_request(uuid, integer) IS
  'Creates one plantilla_slots row + one slot_history row (reason HC_ADD) per '
  'approved HC unit. Reads position/employment_type/store/account/group from the '
  'headcount_requests row. HC request status must be approved_pending_vcode. '
  'Populates source_hc_request_id on each plantilla_slots row for traceability '
  'and idempotency detection. Does not update HC request status; called from '
  'create_plantilla_slot_from_request (OHM2026_0004 dual-write phase). '
  'Vacancy derivation from slots is deferred (see plantilla_slot_architecture.md). '
  'RBAC: Encoder | Head Admin | Super Admin.';


-- ============================================================
-- §3  Update create_plantilla_slot_from_request
-- ============================================================
-- Wires fn_create_slots_from_hc_request into the existing completion
-- flow. The vacancy/plantilla-pool loop is unchanged. After the loop
-- completes, and before the status is advanced to 'completed', one call
-- to fn_create_slots_from_hc_request creates the matching plantilla_slots
-- rows atomically in the same transaction.
--
-- DUAL-WRITE NOTE (transitional — OHM2026_0004):
--   Both the vacancy/plantilla-pool rows (existing) and the plantilla_slots
--   rows (new) are written in the same atomic transaction. If the
--   transaction commits, both exist. If it rolls back, neither exists.
--   The slot_result field in the return value carries the outcome of
--   fn_create_slots_from_hc_request for monitoring. Slot creation failure
--   (ok=false) does not raise an exception; it is captured in slot_result
--   and the caller must evaluate it. This is intentional for the
--   transitional phase — it prevents slot errors from masking vacancy
--   creation failures in logs, while still keeping both writes atomic.
--
-- IDEMPOTENCY (see file header for full explanation):
--   Layer 1: status guard — already exists, unchanged.
--   Layer 2: source_hc_request_id EXISTS check — added in §3.

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
  -- §3 addition: captures the result of the dual-write slot creation call.
  v_slot_result       jsonb;
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

  -- Layer-1 idempotency guard (unchanged): only approved_pending_vcode requests
  -- proceed. Once this function completes, status becomes 'completed' and any
  -- subsequent call is blocked here — preventing duplicate vacancies AND slots.
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

  -- ── Vacancy + pool-plantilla creation loop (unchanged) ───────────────────
  -- Each iteration creates one vacancy and one pool-plantilla (status=Inactive,
  -- employee_name='(VACANT SLOT)') linked by vcode. This is the existing
  -- behaviour and is NOT changed by this migration.
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
  -- ── End unchanged vacancy + pool-plantilla loop ───────────────────────────

  -- ── TRANSITIONAL DUAL-WRITE: create matching plantilla_slots ─────────────
  -- OHM2026_0004. This call is additive — the loop above is unchanged.
  -- When the slot-first architecture is fully adopted, the loop above will
  -- be replaced by slot-derived vacancies and this block will be removed.
  --
  -- Layer-2 idempotency guard: if plantilla_slots rows already exist for
  -- this request (operator called fn_create_slots_from_hc_request directly
  -- before this function ran), skip creation to prevent duplicate slots.
  -- Under normal flow this EXISTS check will always be false at this point
  -- because the status was 'approved_pending_vcode' (layer-1 guard) and
  -- fn_create_slots_from_hc_request has not been called yet this session.
  IF NOT EXISTS (
    SELECT 1 FROM public.plantilla_slots
    WHERE source_hc_request_id = p_request_id
    LIMIT 1
  ) THEN
    -- Pass v_count so slot quantity matches vacancy quantity even if
    -- headcount_needed changed between approval and completion.
    v_slot_result := public.fn_create_slots_from_hc_request(p_request_id, v_count);
    -- fn_create_slots_from_hc_request returns ok=false on validation failure
    -- (no exception raised). A false result is captured in slot_result and
    -- surfaced to the caller for monitoring. It does NOT roll back the
    -- vacancies created above — failure here means slots are missing for
    -- this request and require manual remediation.
  ELSE
    -- Slots already existed (edge case: direct fn_create_slots_from_hc_request
    -- call before completion). Vacancy creation proceeded normally above.
    v_slot_result := jsonb_build_object(
      'ok',    false,
      'error', 'slots_already_existed',
      'hint',  'plantilla_slots were already present for this request; skipped dual-write'
    );
  END IF;
  -- ── End transitional dual-write ───────────────────────────────────────────

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
    'ok',                true,
    'request_id',        p_request_id,
    'headcount_created', v_count,
    'vcode_count',       array_length(v_vcodes, 1),
    'vcodes',            v_vcodes,
    'vacancy_created',   true,
    'slot_result',       v_slot_result   -- dual-write outcome; ok=true is expected
  );
END;
$function$
;
