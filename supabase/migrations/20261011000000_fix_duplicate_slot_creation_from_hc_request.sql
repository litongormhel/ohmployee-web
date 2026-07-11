-- ============================================================================
-- OHM2026_0080 — Fix Duplicate Slot Creation From Completed HC Requests
-- Migration: 20261011000000_fix_duplicate_slot_creation_from_hc_request.sql
-- Depends on:
--   20260821000000_vcode_slot_phase_f_n_slot_creation.sql
--     (create_plantilla_slot_from_request Phase F body, fn_create_slots_from_hc_request(uuid,int,text))
--   20260912000000_backfill_gap_vacancy_slots_and_trigger.sql
--     (fn_trg_auto_create_vacancy_slot + trg_auto_create_vacancy_slot)
--   20260916000000_fix_fractional_hc_vacancy_and_inactive_esa_cleanup.sql
--     (re-created trg_auto_create_vacancy_slot with the same function)
--   20260804000000_plantilla_slot_foundation_v1.sql (plantilla_slots, slot_history, slot_reason_codes)
-- ============================================================================
--
-- ROOT CAUSE (two slot-creation paths collide on HC completion):
--
--   create_plantilla_slot_from_request (Phase F) completes an approved HC
--   request by:
--     1. generating ONE vcode,
--     2. INSERTing ONE vacancies row (required_headcount = N),
--        → this INSERT fires trg_auto_create_vacancy_slot (OHM2026_0070),
--          which creates N plantilla_slots (slot_ordinal 1..N) under that
--          vcode, with source_hc_request_id = NULL.
--     3. running its TRANSITIONAL DUAL-WRITE block, whose Layer-2 idempotency
--        guard checks  EXISTS(plantilla_slots WHERE source_hc_request_id = request).
--        The trigger left source_hc_request_id NULL, so the guard sees NOTHING
--        and calls fn_create_slots_from_hc_request(request, N, vcode), which
--        appends N MORE slots (slot_ordinal N+1..2N).
--
--   Net effect: an HC=N request yields 2N active 'open' slots under one vcode.
--   The vacancy still has required_headcount = N, but every slot-counting
--   surface (vw_slot_derived_vacancy_shadow.open_count, v_account_allocation_kpi
--   .slot_vacant_hc, CENCOM Required/Vacant, Plantilla Required/Vacant, Open
--   badge) counts 2N. Observed: ACTISERVE / SM KALINGA, VCAG5_0057, HC=2,
--   slots ordinals 1-2 (source NULL, trigger) + 3-4 (source set, dual-write)
--   = 4 open slots; expected 2.
--
-- FIX — TWO PARTS:
--
--   §1  create_plantilla_slot_from_request: re-key the dual-write idempotency
--       guard from source_hc_request_id to the freshly generated, globally
--       unique legacy_vcode. The trigger is now the SINGLE forward slot-creation
--       path. When slots already exist for the vcode (normal case — trigger
--       fired on the vacancy INSERT), the function ADOPTS them by stamping
--       source_hc_request_id for traceability and creates NO new slots. The
--       fn_create_slots_from_hc_request call remains only as a defensive
--       fallback for the (abnormal) case where the trigger did not fire.
--       Idempotency is preserved: re-entry is still blocked by the Layer-1
--       status guard (status becomes 'completed'); the vcode-keyed guard
--       additionally prevents any second slot batch.
--
--   §2  One-time cleanup of slots already duplicated by the bug. For every
--       live vacancy whose active (non-closed) slot count exceeds its
--       required_headcount, close the excess. Keep order: occupied >
--       hr_processing > pipeline > open, then lowest slot_ordinal — so bound
--       slots are always retained. Only OPEN, UNBOUND excess slots are closed
--       (archive-first: slot_status='closed', closure_reason_code='HC_REDUCTION',
--       + slot_history). Any excess slot that is NOT open/unbound is left in
--       place and flagged via RAISE NOTICE for manual review (never silently
--       altered). Kept slots with a NULL source_hc_request_id are backfilled
--       from the vacancy's source_headcount_request_id for traceability.
--
-- DELIBERATELY NOT DONE:
--   • No change to the trigger fn_trg_auto_create_vacancy_slot (it is correct —
--     it creates exactly required_headcount slots and is idempotent per
--     (legacy_vcode, slot_ordinal)).
--   • No change to vw_slot_derived_vacancy_shadow (kept slot-derived; closed
--     slots are excluded from open/pipeline/occupied counts already).
--   • No change to vacancy closure logic, Pipeline (applicant) counts, or
--     Hired/Actual (occupied) counts.
--   • No hard deletes — excess slots are closed, with audit trail.
--
-- VALIDATION (see §3 trailing comments; run after applying).
-- ============================================================================

BEGIN;

-- ============================================================================
-- §1  Re-key create_plantilla_slot_from_request idempotency to legacy_vcode
--     (only the dual-write block changes; all other logic identical to Phase F)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_plantilla_slot_from_request(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
/*
  OHM2026_0080 — HC Request completion: one VCODE, exactly N slots.

  Change from Phase F (OHM2026_0052): the transitional dual-write idempotency
  guard is re-keyed from source_hc_request_id to the freshly generated,
  globally unique v_vcode. The auto-create trigger (OHM2026_0070) already
  creates N slots when the vacancy is INSERTed; this function now ADOPTS those
  slots (stamps source_hc_request_id) instead of appending a duplicate batch.
  fn_create_slots_from_hc_request remains a defensive fallback for the case
  where the trigger did not fire.

  Recruitment freeze guard, RBAC, Layer-1 status idempotency, account/store/
  position lookups, single-vacancy (required_headcount=N) insert, pool
  plantilla loop, request status update: all IDENTICAL to Phase F.
*/
DECLARE
  v_role               text := public.get_my_role();
  v_req                public.headcount_requests%ROWTYPE;
  v_account            public.accounts%ROWTYPE;
  v_store              public.stores%ROWTYPE;
  v_position           public.positions%ROWTYPE;
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
BEGIN
  IF NOT (v_role IN ('Encoder', 'Super Admin', 'Head Admin')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  -- Enforce Recruitment Freeze (unchanged)
  PERFORM public.fn_assert_freeze_inactive('recruitment_freeze');

  SELECT * INTO v_req
  FROM public.headcount_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  -- Layer-1 idempotency guard: only approved_pending_vcode proceeds.
  -- Once status becomes 'completed', all subsequent calls are blocked here.
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

  -- ── Generate ONE vcode for this request (unchanged from Phase F) ──────────
  v_vcode  := public.generate_vcode_for_account(v_account.id);
  v_vcodes := ARRAY[v_vcode];

  -- ── Insert ONE vacancy with required_headcount = v_count (unchanged) ──────
  -- NOTE: this INSERT fires trg_auto_create_vacancy_slot, which creates the
  -- N slots (ordinals 1..N) for v_vcode. The dual-write block below adopts
  -- those slots rather than creating a second batch.
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

  -- ── Pool plantilla loop — N rows, all under the single vcode (unchanged) ──
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

  -- Link the single vacancy to the first pool plantilla row (unchanged)
  UPDATE public.vacancies
  SET source_plantilla_id = v_first_plantilla_id,
      updated_by          = v_triggered_by_id
  WHERE id = v_vacancy_id;

  -- ── OHM2026_0080: slot creation is owned by the auto-create trigger ───────
  -- Idempotency is keyed on v_vcode (freshly generated, globally unique).
  -- Normal path: the vacancy INSERT above already created N slots via
  -- trg_auto_create_vacancy_slot → adopt them (stamp source_hc_request_id),
  -- creating NO duplicate batch. Fallback: if no slots exist for the vcode
  -- (trigger disabled/absent), create them directly.
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
    'vcode_count',       1,
    'vcodes',            v_vcodes,
    'vacancy_created',   true,
    'slot_result',       v_slot_result
  );
END;
$function$;

COMMENT ON FUNCTION public.create_plantilla_slot_from_request(uuid) IS
  'OHM2026_0080: HC Request completion producing one VCODE per request with '
  'exactly required_headcount slots. Slot creation is owned by '
  'trg_auto_create_vacancy_slot (fires on the vacancy INSERT); this function '
  'adopts those slots (stamps source_hc_request_id) under a v_vcode-keyed '
  'idempotency guard rather than appending a duplicate batch (fixes the '
  'duplicate-slot bug from the Phase F source_hc_request_id-keyed guard). '
  'fn_create_slots_from_hc_request is a defensive fallback when the trigger '
  'did not fire. HC=N: one vcode, one vacancy (required_headcount=N), N slots.';

REVOKE ALL ON FUNCTION public.create_plantilla_slot_from_request(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_plantilla_slot_from_request(uuid) TO authenticated;


-- ============================================================================
-- §2  One-time cleanup: close duplicate slots beyond required_headcount
-- ============================================================================
-- Archive-first. Keeps bound slots (occupied > hr_processing > pipeline >
-- open) and lowest ordinals; closes only OPEN + UNBOUND excess. Any other
-- excess slot is left in place and flagged for manual review.

DO $$
DECLARE
  v_vac       record;
  v_slot      record;
  v_rank      int;
  v_closed    int := 0;
  v_unsafe    int := 0;
  v_backfill  int := 0;
BEGIN
  FOR v_vac IN
    SELECT v.vcode,
           GREATEST(ROUND(v.required_headcount)::int, 1) AS required_hc,
           v.account_id,
           v.source_headcount_request_id
    FROM public.vacancies v
    WHERE v.deleted_at IS NULL
      AND v.vcode IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.plantilla_slots ps
        WHERE ps.legacy_vcode = v.vcode
          AND ps.is_roving = false
          AND ps.slot_status <> 'closed'
        GROUP BY ps.legacy_vcode
        HAVING COUNT(*) > GREATEST(ROUND(v.required_headcount)::int, 1)
      )
  LOOP
    -- Traceability backfill on retained-eligible active slots.
    IF v_vac.source_headcount_request_id IS NOT NULL THEN
      UPDATE public.plantilla_slots
      SET source_hc_request_id = v_vac.source_headcount_request_id,
          updated_at           = now()
      WHERE legacy_vcode = v_vac.vcode
        AND slot_status <> 'closed'
        AND source_hc_request_id IS NULL;
      GET DIAGNOSTICS v_backfill = ROW_COUNT;
    END IF;

    v_rank := 0;
    FOR v_slot IN
      SELECT id, slot_ordinal, slot_status, current_occupant_plantilla_id
      FROM public.plantilla_slots
      WHERE legacy_vcode = v_vac.vcode
        AND is_roving = false
        AND slot_status <> 'closed'
      ORDER BY
        CASE slot_status
          WHEN 'occupied'      THEN 0
          WHEN 'hr_processing' THEN 1
          WHEN 'pipeline'      THEN 2
          ELSE 3
        END,
        slot_ordinal
    LOOP
      v_rank := v_rank + 1;

      -- Keep the first required_hc slots.
      IF v_rank <= v_vac.required_hc THEN
        CONTINUE;
      END IF;

      -- Excess slot. Close only if open & unbound (safe); otherwise flag.
      IF v_slot.slot_status = 'open' AND v_slot.current_occupant_plantilla_id IS NULL THEN
        UPDATE public.plantilla_slots
        SET slot_status         = 'closed',
            closed_at           = now(),
            closure_reason_code = 'HC_REDUCTION',
            updated_at          = now()
        WHERE id = v_slot.id;

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type, old_value, new_value,
          reason_code, performed_by, remarks
        ) VALUES (
          v_slot.id, v_vac.account_id, 'status_change', 'open', 'closed',
          'HC_REDUCTION', NULL,
          'OHM2026_0080 cleanup — closed duplicate slot (ordinal '
            || v_slot.slot_ordinal || ') exceeding required_headcount for '
            || v_vac.vcode
        );

        v_closed := v_closed + 1;
      ELSE
        v_unsafe := v_unsafe + 1;
        RAISE NOTICE 'OHM2026_0080: vcode % excess slot % status % is bound/non-open — left for manual review',
          v_vac.vcode, v_slot.id, v_slot.slot_status;
      END IF;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'OHM2026_0080 cleanup: % duplicate slot(s) closed, % excess slot(s) flagged, % linkage backfill(s).',
    v_closed, v_unsafe, v_backfill;
END$$;

COMMIT;

-- ============================================================================
-- §3  Post-migration validation (run manually)
-- ============================================================================
--
-- V1 — Target request HC-2E2B4CDC (VCAG5_0057): exactly 2 active slots.
--   SELECT COUNT(*) FROM public.plantilla_slots
--   WHERE source_hc_request_id = '2e2b4cdc-1a10-47e6-b68f-2239fcb9e200'
--     AND slot_status <> 'closed';
--   -- Expect: 2
--
-- V2 — VCAG5_0057: exactly 2 active slots, 2 closed (the duplicates).
--   SELECT slot_status, COUNT(*) FROM public.plantilla_slots
--   WHERE legacy_vcode = 'VCAG5_0057' GROUP BY slot_status;
--   -- Expect: open=2, closed=2
--
-- V3 — Shadow view for VCAG5_0057: required_headcount (HC Needed) = 2, open = 2.
--   SELECT required_headcount, open_count, occupied_count, closed_count
--   FROM public.vw_slot_derived_vacancy_shadow WHERE legacy_vcode = 'VCAG5_0057';
--   -- Expect: required_headcount=2, open_count=2.
--
-- V4 — No vacancy retains more active slots than its required_headcount.
--   WITH active_slots AS (
--     SELECT ps.legacy_vcode, COUNT(*) AS active_cnt
--     FROM public.plantilla_slots ps
--     WHERE ps.legacy_vcode IS NOT NULL AND ps.is_roving = false
--       AND ps.slot_status <> 'closed'
--     GROUP BY ps.legacy_vcode
--   )
--   SELECT s.legacy_vcode, s.active_cnt, ROUND(v.required_headcount)::int AS required_hc
--   FROM active_slots s
--   JOIN public.vacancies v ON v.vcode = s.legacy_vcode AND v.deleted_at IS NULL
--   WHERE s.active_cnt > GREATEST(ROUND(v.required_headcount)::int, 1);
--   -- Expect: 0 rows.
--
-- V5 — slot_vacant_hc for ACTISERVE reflects 2 (bypass SECURITY INVOKER).
--   SELECT COUNT(*) AS slot_vacant_hc
--   FROM public.plantilla_slots ps
--   INNER JOIN public.vacancies v ON v.vcode = ps.legacy_vcode
--     AND v.deleted_at IS NULL AND COALESCE(v.is_archived,false)=false
--     AND COALESCE(v.is_pool_vacancy,false)=false
--   WHERE ps.legacy_vcode = 'VCAG5_0057'
--     AND ps.slot_status IN ('open','pipeline')
--     AND ps.is_roving = false;
--   -- Expect: 2.
--
-- V6 — Idempotency: re-running the slot creation RPC for the same (completed)
--      request creates NO new slots.
--   SELECT public.fn_create_slots_from_hc_request(
--            '2e2b4cdc-1a10-47e6-b68f-2239fcb9e200'::uuid, 2, 'VCAG5_0057');
--   -- Expect: ok=false, error='request_not_in_approved_state' (status=completed).
--   -- Slot count for VCAG5_0057 unchanged (still open=2, closed=2).
--
-- V7 — Forward path: a NEW HC=N request completion yields exactly N active
--      slots (no duplicate). After completing a fresh approved HC=N request:
--   SELECT COUNT(*) FILTER (WHERE slot_status <> 'closed') AS active_slots
--   FROM public.plantilla_slots WHERE legacy_vcode = '<new_vcode>';
--   -- Expect: N (not 2N).
-- ============================================================================
