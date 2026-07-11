-- ============================================================
-- OHM2026_0007 — Add Legacy VCODE Bridge to Plantilla Slots
-- Migration: 20260807000000_plantilla_slots_legacy_vcode_link.sql
-- Depends on:
--   20260804000000_plantilla_slot_foundation_v1.sql
--     (plantilla_slots, slot_history, slot_reason_codes)
--   20260805000000_fn_create_slots_from_hc_request.sql
--     (fn_create_slots_from_hc_request)
--   20260806000000_wire_slot_creation_into_hc_completion.sql
--     (source_hc_request_id on plantilla_slots; dual-write wiring)
--   Pre-existing: vacancies (vcode PK), headcount_requests,
--     accounts, groups, stores, positions, plantilla, users_profile
--   Pre-existing helpers: get_my_role(), get_current_profile_id(),
--     i_have_full_access(), fn_assert_freeze_inactive(),
--     generate_vcode_for_account()
-- ============================================================
-- Scope: TRANSITIONAL VCODE BRIDGE — additive, no behavior change.
--
-- Context (see docs/architecture/slot_derived_vacancy_read_model.md §8):
--   The slot-derived Vacancy read model design (OHM2026_0006) identified
--   VCODE as the bridge between plantilla_slots and the legacy vacancies /
--   applicants tables. VCODE is the permanent manpower-slot lifecycle ID
--   (OHM2026_1144) shared across vacancies, plantilla, and applicants.
--   Adding it to plantilla_slots makes each slot 1:1 reconcilable with its
--   matching legacy vacancy row, enabling the shadow reconciliation phase
--   (Phase 3 / Phase 4 of the read-model adoption sequence).
--
-- Sections:
--   §1  Add nullable legacy_vcode to plantilla_slots + index
--   §2  Update fn_create_slots_from_hc_request — accept p_vcodes[], populate legacy_vcode
--   §3  Update create_plantilla_slot_from_request — pass v_vcodes to slot RPC
--
-- This migration deliberately does NOT:
--   • alter Vacancy / HR Emploc / Plantilla / Transfer / Import behavior,
--   • change the vacancy/plantilla-pool loop inside
--     create_plantilla_slot_from_request,
--   • create the slot-derived Vacancy view (Phase 3 — deferred),
--   • migrate or backfill existing data (pre-migration slots keep NULL legacy_vcode),
--   • advance headcount_requests.status beyond what already existed,
--   • touch MFR / CENCOM.
--   No existing UI behavior changes. No existing table is removed or renamed.
--
-- LEGACY_VCODE POPULATION STRATEGY:
--   VCODEs are generated inside create_plantilla_slot_from_request's vacancy
--   loop (one per iteration, stored in v_vcodes[]). After the loop,
--   fn_create_slots_from_hc_request is called and now receives the vcodes
--   array as p_vcodes. Slots are created in the same iteration order (1..N),
--   so slot i receives p_vcodes[i]. Both writes remain in the same atomic
--   transaction — if either rolls back, neither vacancy nor slot is committed.
--   When fn_create_slots_from_hc_request is called standalone (not from the
--   dual-write path), p_vcodes defaults to NULL and legacy_vcode stays NULL
--   on all created slots, which is expected and correct.
--
-- LIMITATIONS FOR PRE-EXISTING SLOTS:
--   Slots created by the 20260806000000 dual-write before this migration was
--   applied will have legacy_vcode = NULL. These can be reconciled via
--   source_hc_request_id (join to vacancies.source_headcount_request_id)
--   when accurate 1:1 VCODE assignment is needed. No automated backfill is
--   performed here — backfill is out of scope per OHM2026_0007.
--
-- Validation Queries (run manually after applying):
--   V1 – Column exists
--     SELECT column_name, data_type, is_nullable
--       FROM information_schema.columns
--       WHERE table_schema = 'public'
--         AND table_name   = 'plantilla_slots'
--         AND column_name  = 'legacy_vcode';
--   V2 – Index exists
--     SELECT indexname FROM pg_indexes
--       WHERE schemaname = 'public'
--         AND tablename  = 'plantilla_slots'
--         AND indexname  = 'idx_plantilla_slots_legacy_vcode';
--   V3 – New HC request completion populates legacy_vcode
--     -- After completing an HC request, run:
--     SELECT ps.id, ps.legacy_vcode, v.vcode, v.status
--       FROM public.plantilla_slots ps
--       JOIN public.vacancies v
--         ON v.vcode = ps.legacy_vcode
--       WHERE ps.source_hc_request_id = '<completed_request_id>'
--       ORDER BY ps.created_at;
--     -- Expect: one row per approved HC unit, legacy_vcode = matching vcode
--   V4 – Legacy vacancies still created correctly (behavior unchanged)
--     SELECT vcode, status, account_id, store_id, employment_type, position
--       FROM public.vacancies
--       WHERE source_headcount_request_id = '<completed_request_id>';
--   V5 – Pre-existing slots retain NULL legacy_vcode (expected)
--     SELECT COUNT(*) as null_vcode_slots
--       FROM public.plantilla_slots
--       WHERE legacy_vcode IS NULL;
--     -- Should include rows created by 20260806000000 before this migration.
--   V6 – No duplicate slot check (unchanged guard)
--     SELECT source_hc_request_id, COUNT(*) as slot_count
--       FROM public.plantilla_slots
--       WHERE source_hc_request_id IS NOT NULL
--       GROUP BY source_hc_request_id
--       HAVING COUNT(*) > 1;
--     -- Expect: empty result set.
-- ============================================================


-- ============================================================
-- §1  Add legacy_vcode to plantilla_slots
-- ============================================================
-- TRANSITIONAL BRIDGE COLUMN (OHM2026_0007):
--   Stores the vcode of the matching legacy vacancy row created in the
--   same atomic HC request completion transaction. Enables 1:1 slot ↔
--   legacy-vacancy reconciliation required for the slot-derived Vacancy
--   read model shadow phase (OHM2026_0006, Phase 3).
--
--   NULL is expected for:
--     • Slots created before this migration was applied.
--     • Slots created via future non-HC-request workflows (resignation
--       refill, manual creation) where no legacy vacancy counterpart exists.
--     • Slots created by a direct fn_create_slots_from_hc_request call
--       (standalone, without a vcodes array supplied).
--
--   When the slot-derived Vacancy read model is fully adopted and the
--   dual-write loop is retired, this column becomes the permanent 1:1
--   applicant↔slot bridge reusing VCODE as the shared lifecycle ID.

ALTER TABLE public.plantilla_slots
  ADD COLUMN IF NOT EXISTS legacy_vcode text;

COMMENT ON COLUMN public.plantilla_slots.legacy_vcode IS
  'TRANSITIONAL BRIDGE (OHM2026_0007): The vcode of the matching legacy '
  'vacancies row created in the same HC request completion transaction. '
  'Populated by the dual-write path in create_plantilla_slot_from_request; '
  'NULL for pre-migration slots and any slot created outside the HC request '
  'workflow. Enables 1:1 slot↔legacy-vacancy reconciliation for the '
  'slot-derived Vacancy read model shadow phase (OHM2026_0006, Phase 3). '
  'When the slot-first architecture is fully adopted this becomes the '
  'permanent applicant↔slot VCODE bridge.';

-- Partial index: only non-NULL vcodes are looked up in reconciliation and
-- shadow-view queries; NULL rows are not worth indexing.
CREATE INDEX IF NOT EXISTS idx_plantilla_slots_legacy_vcode
  ON public.plantilla_slots(legacy_vcode)
  WHERE legacy_vcode IS NOT NULL;


-- ============================================================
-- §2  Update fn_create_slots_from_hc_request
-- ============================================================
-- Adds optional p_vcodes text[] parameter. When supplied (normal dual-write
-- path), each slot i receives p_vcodes[i] in the legacy_vcode column so
-- the slot is 1:1 reconcilable with its matching legacy vacancy.
-- When p_vcodes is NULL (standalone call), legacy_vcode stays NULL on
-- all created slots — correct for the standalone use case where no legacy
-- vacancies are being co-created.
-- All other behaviour is identical to the 20260806000000 version.

CREATE OR REPLACE FUNCTION public.fn_create_slots_from_hc_request(
  p_request_id uuid,
  p_quantity   integer DEFAULT NULL,
  p_vcodes     text[]  DEFAULT NULL   -- §2 addition: per-slot VCODE bridge
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
  v_slot_vcode      text;             -- §2 addition: per-slot vcode resolved from p_vcodes
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

    -- §2: Resolve the matching vcode for this slot iteration.
    -- p_vcodes[i] is the vcode generated for the i-th vacancy in the
    -- create_plantilla_slot_from_request vacancy loop (same iteration order).
    -- NULL when p_vcodes is not supplied (standalone call) or too short.
    v_slot_vcode := CASE
      WHEN p_vcodes IS NOT NULL AND cardinality(p_vcodes) >= i
      THEN p_vcodes[i]
      ELSE NULL
    END;

    INSERT INTO public.plantilla_slots (
      store_id,
      account_id,
      group_id,
      position,
      employment_type,
      is_roving,
      slot_status,
      source_hc_request_id,
      legacy_vcode,           -- §2 addition: 1:1 link to matching legacy vacancy
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
      p_request_id,
      v_slot_vcode,           -- §2 addition; NULL when p_vcodes not supplied
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
        'Slot %s of %s created from HC request %s — %s %s%s',
        i, v_qty,
        p_request_id::text,
        v_employment_type,
        v_position_name,
        CASE WHEN v_slot_vcode IS NOT NULL
             THEN ' [vcode=' || v_slot_vcode || ']'
             ELSE '' END
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

COMMENT ON FUNCTION public.fn_create_slots_from_hc_request(uuid, integer, text[]) IS
  'Creates one plantilla_slots row + one slot_history row (reason HC_ADD) per '
  'approved HC unit. Reads position/employment_type/store/account/group from the '
  'headcount_requests row. HC request status must be approved_pending_vcode. '
  'Populates source_hc_request_id on each plantilla_slots row for traceability '
  'and idempotency detection. '
  'p_vcodes (optional): when supplied by create_plantilla_slot_from_request, '
  'each slot i receives p_vcodes[i] in legacy_vcode for 1:1 slot↔vacancy '
  'reconciliation (OHM2026_0007 VCODE bridge). NULL when called standalone. '
  'Does not update HC request status; called from create_plantilla_slot_from_request '
  '(OHM2026_0004 dual-write phase, extended OHM2026_0007). '
  'Vacancy derivation from slots is deferred (see plantilla_slot_architecture.md). '
  'RBAC: Encoder | Head Admin | Super Admin.';


-- ============================================================
-- §3  Update create_plantilla_slot_from_request
-- ============================================================
-- Passes v_vcodes (already collected by the vacancy loop) to
-- fn_create_slots_from_hc_request so each new slot receives its
-- matching legacy_vcode. All other behaviour is identical to the
-- 20260806000000 version.
--
-- DUAL-WRITE NOTE (OHM2026_0004 / OHM2026_0007):
--   The vacancy/plantilla-pool loop is unchanged. The only change vs the
--   20260806000000 version is the third argument (v_vcodes) passed to
--   fn_create_slots_from_hc_request. Both vacancy rows (carrying vcodes)
--   and plantilla_slots rows (carrying matching legacy_vcode) are committed
--   or rolled back together in the same atomic transaction.

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
  -- OHM2026_0004 / OHM2026_0007. The loop above is unchanged.
  -- v_vcodes[] (one entry per vacancy created above) is passed so each slot
  -- receives its matching legacy_vcode for 1:1 reconciliation.
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
    -- §3 change vs 20260806000000: pass v_vcodes as third argument so each
    -- slot receives its matching legacy_vcode (OHM2026_0007 VCODE bridge).
    v_slot_result := public.fn_create_slots_from_hc_request(p_request_id, v_count, v_vcodes);
    -- fn_create_slots_from_hc_request returns ok=false on validation failure
    -- (no exception raised). A false result is captured in slot_result and
    -- surfaced to the caller for monitoring. It does NOT roll back the
    -- vacancies created above — failure here means slots are missing for
    -- this request and require manual remediation.
  ELSE
    -- Slots already existed (edge case: direct fn_create_slots_from_hc_request
    -- call before completion). Vacancy creation proceeded normally above.
    -- legacy_vcode will be NULL on those pre-existing slots.
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
