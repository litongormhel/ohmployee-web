-- Migration: 20261216000000_fix_hc_request_duplicate_vcode_per_store.sql
-- Ticket: ohm#9kq4m2z8 — Fix duplicate VCODE creation for same store headcount requests
--
-- Root Cause:
--   create_plantilla_slot_from_request (stationary path) always mints a new VCODE
--   via generate_vcode_for_account() regardless of whether the same store already
--   has an active vacancy under an existing VCODE.
--   Rule: 1 store = 1 active VCODE.
--   Completing a second HC request for the same store (e.g., SM BAY / KAMBAK) must
--   reuse the existing active vacancy's VCODE rather than mint a new one.
--
-- Fix:
--   §1  New helper: find_reusable_store_vcode(p_account_id, p_store_id, p_store_name)
--       Returns the vcode of the first active non-pool non-archived vacancy for the
--       given store, or NULL if none exists.
--       Primary match: store_id (UUID FK — most reliable).
--       Fallback match: account_id + case-insensitive store_name (when store_id NULL).
--
--   §2  Updated create_plantilla_slot_from_request (stationary path only):
--       Before minting a new VCODE, call find_reusable_store_vcode.
--       Reuse path (existing active vacancy found):
--         - Use existing VCODE; skip INSERT into vacancies.
--         - Increment required_headcount on the existing vacancy by v_count.
--         - Insert plantilla (VACANT SLOT) rows linked to the reused VCODE.
--         - Return reused_vcode=true in the response.
--       New-VCODE path (no existing active vacancy):
--         - Mint new VCODE and INSERT new vacancy as before (unchanged).
--
-- Not changed:
--   - Roving path (coverage groups, unaffected).
--   - Pool vacancies (excluded from reuse lookup by is_pool_vacancy guard).
--   - Vacancy import behavior.
--   - Coverage group behavior.
--   - approve_vacancy_request_auto_vcodes (separate pathway, unaffected).
--   - All other VCODE generation functions.
--
-- Smoke tests:
--   T1: First HC request for SM BAY creates VCKG3_XXXX — new vacancy row inserted.
--   T2: Second HC request for same SM BAY reuses VCKG3_XXXX — no new vacancy row;
--       required_headcount incremented; new plantilla (VACANT SLOT) row created.
--   T3: HC request for different store gets a different VCODE — new vacancy row.
--   T4: Archived/closed vacancy does not block a new VCODE (excluded from lookup).
-- ─────────────────────────────────────────────────────────────────────────────


-- ─────────────────────────────────────────────────────────────────────────────
-- §1  Helper: find_reusable_store_vcode
-- ─────────────────────────────────────────────────────────────────────────────
-- Returns the vcode of the first active, non-archived, non-pool vacancy for
-- the given store. Returns NULL if no reusable vacancy exists.
--
-- Matching priority:
--   1. store_id match (UUID FK) when p_store_id IS NOT NULL.
--   2. Fallback: account_id + case-insensitive store_name when p_store_id IS NULL.
--
-- Excluded from reuse:
--   - is_archived = true  (closed/archived vacancies do not block new VCODEs)
--   - deleted_at IS NOT NULL (soft-deleted)
--   - is_pool_vacancy = true (pool architecture is separate)
--   - status NOT IN ('Open', 'Pipeline')
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.find_reusable_store_vcode(
  p_account_id  uuid,
  p_store_id    uuid,
  p_store_name  text
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_vcode text;
BEGIN
  IF p_store_id IS NOT NULL THEN
    -- Primary: match by store UUID
    SELECT vcode INTO v_vcode
    FROM public.vacancies
    WHERE account_id                       = p_account_id
      AND store_id                         = p_store_id
      AND status                           IN ('Open', 'Pipeline')
      AND COALESCE(is_archived, false)     = false
      AND deleted_at                       IS NULL
      AND COALESCE(is_pool_vacancy, false) = false
    ORDER BY created_at ASC
    LIMIT 1;
  END IF;

  IF v_vcode IS NULL AND p_store_name IS NOT NULL THEN
    -- Fallback: match by account_id + normalised store name
    SELECT vcode INTO v_vcode
    FROM public.vacancies
    WHERE account_id                       = p_account_id
      AND LOWER(TRIM(store_name))          = LOWER(TRIM(p_store_name))
      AND status                           IN ('Open', 'Pipeline')
      AND COALESCE(is_archived, false)     = false
      AND deleted_at                       IS NULL
      AND COALESCE(is_pool_vacancy, false) = false
    ORDER BY created_at ASC
    LIMIT 1;
  END IF;

  RETURN v_vcode; -- NULL if no reusable vacancy found
END;
$$;

COMMENT ON FUNCTION public.find_reusable_store_vcode(uuid, uuid, text) IS
  'Returns the vcode of the first active non-archived non-pool vacancy for the '
  'given store (matched by store_id first, then account_id+store_name). '
  'Returns NULL when no reusable vacancy exists. '
  'Used by create_plantilla_slot_from_request to enforce 1-store-1-VCODE rule.';

GRANT EXECUTE ON FUNCTION public.find_reusable_store_vcode(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.find_reusable_store_vcode(uuid, uuid, text) TO service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- §2  Updated create_plantilla_slot_from_request
--     Stationary path: reuse existing store VCODE before minting a new one.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_plantilla_slot_from_request(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role               text := public.get_my_role();
  v_req                public.headcount_requests%ROWTYPE;
  v_account            public.accounts%ROWTYPE;
  v_store              public.stores%ROWTYPE;
  v_position           public.positions%ROWTYPE;
  v_coverage_group     public.coverage_groups%ROWTYPE;
  v_store_name         text;
  v_store_id           uuid;
  v_vcode              text;
  v_vcodes             text[];
  v_plantilla_id       uuid;
  v_vacancy_id         uuid;
  v_first_plantilla_id uuid;
  v_count              integer;
  i                    integer;
  v_triggered_by_id    uuid;
  v_triggered_by_name  text;
  v_hrco_user_id       uuid;
  v_hrco_name          text;
  v_group_id           uuid;
  v_group_name         text;
  v_slot_result        jsonb;
  v_max_ordinal        integer;
  -- ohm#9kq4m2z8: VCODE reuse fields
  v_reused_vcode       boolean := false;
BEGIN
  IF NOT (v_role IN ('Encoder', 'Super Admin', 'Head Admin')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

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

  v_triggered_by_id := public.get_current_profile_id();
  SELECT full_name INTO v_triggered_by_name
  FROM public.users_profile WHERE id = v_triggered_by_id;

  -- ── Roving path (unchanged) ────────────────────────────────────────────────
  IF lower(coalesce(v_req.workforce_type, 'stationary')) = 'roving' THEN
    IF v_req.coverage_group_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'coverage_group_required_for_roving');
    END IF;

    SELECT * INTO v_coverage_group
    FROM public.coverage_groups
    WHERE id = v_req.coverage_group_id
      AND account_id = v_req.account_id
      AND archived_at IS NULL
    FOR UPDATE;

    IF v_coverage_group.id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'coverage_group_id');
    END IF;

    IF v_coverage_group.position_id <> v_req.position_id THEN
      RETURN jsonb_build_object('ok', false, 'error', 'coverage_group_position_mismatch');
    END IF;

    SELECT COALESCE(MAX(slot_ordinal), 0)
      INTO v_max_ordinal
    FROM public.coverage_slots
    WHERE coverage_group_id = v_coverage_group.id;

    INSERT INTO public.coverage_slots (coverage_group_id, slot_ordinal, slot_status)
    SELECT v_coverage_group.id, v_max_ordinal + gs.ord, 'open'
    FROM generate_series(1, v_count) AS gs(ord);

    UPDATE public.coverage_groups
    SET required_headcount = required_headcount + v_count,
        status = 'open'
    WHERE id = v_coverage_group.id;

    UPDATE public.headcount_requests
    SET status = 'completed',
        vacancy_created = true,
        slot_created_by_user_id = v_triggered_by_id,
        slot_created_at = NOW(),
        coverage_group_code_snapshot = COALESCE(coverage_group_code_snapshot, v_coverage_group.coverage_code),
        created_vcode = NULL,
        created_vcodes = ARRAY[]::text[]
    WHERE id = p_request_id;

    RETURN jsonb_build_object(
      'ok', true,
      'request_id', p_request_id,
      'headcount_created', v_count,
      'workforce_type', 'roving',
      'coverage_group_id', v_coverage_group.id,
      'coverage_code', v_coverage_group.coverage_code,
      'coverage_slots_created', v_count,
      'vacancy_created', true
    );
  END IF;

  IF lower(coalesce(v_req.workforce_type, 'stationary')) = 'floating' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'floating_workforce_not_enabled');
  END IF;

  -- ── Stationary path ────────────────────────────────────────────────────────

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

  v_hrco_user_id := v_account.hrco_user_id;
  IF v_hrco_user_id IS NOT NULL THEN
    SELECT full_name INTO v_hrco_name
    FROM public.users_profile WHERE id = v_hrco_user_id;
  END IF;

  -- ── ohm#9kq4m2z8: 1-store-1-VCODE reuse check ─────────────────────────────
  -- Before minting a new VCODE, look for an existing active non-archived
  -- non-pool vacancy for this store. Reuse it if found.
  v_vcode := public.find_reusable_store_vcode(v_account.id, v_store_id, v_store_name);

  IF v_vcode IS NOT NULL THEN
    -- Reuse path: existing active vacancy found — attach slots to it.
    v_reused_vcode := true;

    SELECT id INTO v_vacancy_id
    FROM public.vacancies
    WHERE vcode                          = v_vcode
      AND status                         IN ('Open', 'Pipeline')
      AND COALESCE(is_archived, false)   = false
      AND deleted_at                     IS NULL
    LIMIT 1;

    IF v_vacancy_id IS NULL THEN
      -- Defensive: reusable VCODE disappeared between find and lock — fall through
      -- to new VCODE creation to avoid a silent failure.
      RAISE WARNING
        '[ohm#9kq4m2z8] Reusable VCODE % found but vacancy row missing — minting new VCODE for HC request %',
        v_vcode, p_request_id;
      v_vcode        := public.generate_vcode_for_account(v_account.id);
      v_reused_vcode := false;

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
        COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
        v_store_name,
        COALESCE(v_req.vacant_date, CURRENT_DATE),
        v_count,
        NULL,
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
    ELSE
      -- Normal reuse: increment required_headcount on the existing vacancy
      UPDATE public.vacancies
      SET required_headcount = required_headcount + v_count,
          updated_by         = v_triggered_by_id,
          updated_at         = NOW()
      WHERE id = v_vacancy_id;

      RAISE LOG
        '[ohm#9kq4m2z8] HC request % reusing VCODE % (vacancy %) for store % — required_headcount incremented by %',
        p_request_id, v_vcode, v_vacancy_id, v_store_name, v_count;
    END IF;

  ELSE
    -- New-VCODE path: no active vacancy exists for this store — mint a new VCODE.
    v_vcode := public.generate_vcode_for_account(v_account.id);

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
      COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
      v_store_name,
      COALESCE(v_req.vacant_date, CURRENT_DATE),
      v_count,
      NULL,
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
  END IF;

  v_vcodes := ARRAY[v_vcode];

  -- ── Plantilla (VACANT SLOT) rows — always created for every headcount unit ──
  FOR i IN 1..v_count LOOP
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
      v_account.id, v_store_id,
      COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
      v_position.id,
      v_store_name, v_req.employment_type,
      p_request_id,
      v_group_id,
      v_triggered_by_id, v_triggered_by_id, CURRENT_DATE
    ) RETURNING id INTO v_plantilla_id;

    IF v_first_plantilla_id IS NULL THEN
      v_first_plantilla_id := v_plantilla_id;
    END IF;
  END LOOP;

  -- Link vacancy back to first plantilla if this was a new vacancy
  IF NOT v_reused_vcode THEN
    UPDATE public.vacancies
    SET source_plantilla_id = v_first_plantilla_id,
        updated_by          = v_triggered_by_id
    WHERE id = v_vacancy_id;
  END IF;

  -- ── Dual-write: plantilla_slots (unchanged slot linkage logic) ─────────────
  IF EXISTS (
    SELECT 1 FROM public.plantilla_slots
    WHERE legacy_vcode = v_vcode
    LIMIT 1
  ) THEN
    UPDATE public.plantilla_slots
    SET source_hc_request_id = p_request_id,
        updated_by           = v_triggered_by_id,
        updated_at           = now()
    WHERE legacy_vcode = v_vcode
      AND source_hc_request_id IS NULL;

    v_slot_result := jsonb_build_object(
      'ok',      true,
      'adopted', true,
      'hint',    'slots created by trg_auto_create_vacancy_slot; linked to HC request'
    );
  ELSE
    v_slot_result := public.fn_create_slots_from_hc_request(p_request_id, v_count, v_vcode);
  END IF;

  UPDATE public.headcount_requests
  SET status                   = 'completed',
      vacancy_created          = true,
      slot_created_by_user_id  = v_triggered_by_id,
      slot_created_at          = NOW(),
      created_plantilla_id     = v_first_plantilla_id,
      created_vcode            = v_vcode,
      created_vcodes           = v_vcodes
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'ok',                true,
    'request_id',        p_request_id,
    'headcount_created', v_count,
    'workforce_type',    'stationary',
    'vcode_count',       1,
    'vcodes',            v_vcodes,
    'vacancy_created',   true,
    'reused_vcode',      v_reused_vcode,
    'slot_result',       v_slot_result
  );
END;
$function$;

COMMENT ON FUNCTION public.create_plantilla_slot_from_request(uuid) IS
  'Completes an approved HC request by creating a vacancy + plantilla (VACANT SLOT) rows. '
  'Stationary path: enforces 1-store-1-VCODE by reusing the existing active vacancy VCODE '
  'when the store already has one (ohm#9kq4m2z8). Roving path: adds coverage_slots and '
  'increments the coverage group headcount. Returns reused_vcode=true when reuse occurred.';


-- ─────────────────────────────────────────────────────────────────────────────
-- Validation queries (run against staging / live before prod)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- V1 — Helper function exists:
--   SELECT proname FROM pg_proc
--   WHERE proname = 'find_reusable_store_vcode'
--     AND pronamespace = 'public'::regnamespace;
--   Expected: 1 row.
--
-- V2 — No reuse when store has no active vacancy:
--   SELECT public.find_reusable_store_vcode(
--     '<account_id_with_no_open_vacancy>'::uuid,
--     '<store_id>'::uuid,
--     'SM BAY'
--   );
--   Expected: NULL.
--
-- V3 — Reuse returns existing VCODE:
--   SELECT public.find_reusable_store_vcode(
--     '<account_id>'::uuid,
--     '<store_id_with_open_vacancy>'::uuid,
--     'SM BAY'
--   );
--   Expected: '<existing_vcode>' (e.g., VCKG3_0002).
--
-- V4 — T1: First HC request for SM BAY creates new VCODE
--   SELECT public.create_plantilla_slot_from_request('<first_approved_request_id>'::uuid);
--   Expected: ok=true, reused_vcode=false, vcodes=['VCKG3_XXXX']
--   Check: SELECT COUNT(*) FROM public.vacancies WHERE store_id = '<sm_bay_store_id>';
--   Expected: 1 row.
--
-- V5 — T2: Second HC request for same SM BAY reuses VCODE
--   SELECT public.create_plantilla_slot_from_request('<second_approved_request_id>'::uuid);
--   Expected: ok=true, reused_vcode=true, vcodes=['VCKG3_XXXX'] (same VCODE)
--   Check: SELECT COUNT(*) FROM public.vacancies WHERE store_id = '<sm_bay_store_id>';
--   Expected: still 1 row (no new vacancy created).
--   Check: SELECT required_headcount FROM public.vacancies WHERE vcode = 'VCKG3_XXXX';
--   Expected: original_count + second_request_headcount.
--
-- V6 — T3: HC request for different store still creates new VCODE
--   SELECT public.create_plantilla_slot_from_request('<other_store_request_id>'::uuid);
--   Expected: ok=true, reused_vcode=false, different VCODE.
--
-- V7 — T4: Archived vacancy does not block new VCODE
--   -- Ensure SM BAY vacancy is archived: is_archived=true.
--   SELECT public.find_reusable_store_vcode('<account_id>'::uuid, '<store_id>'::uuid, 'SM BAY');
--   Expected: NULL (archived vacancy excluded).
--   Then complete HC request — should mint a new VCODE.
