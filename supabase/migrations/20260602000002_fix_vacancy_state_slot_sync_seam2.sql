-- ============================================================
-- OHM2026_0131 — Fix Vacancy State: Add Slot Sync Hook to fn_update_applicant_pipeline
-- Migration: 20260602000002_fix_vacancy_state_slot_sync_seam2.sql
--
-- Depends on:
--   20260828000000_applicant_pipeline_seam2_rpcs.sql
--     (fn_update_applicant_pipeline — SEAM 2 base)
--   20260817000000_vcode_slot_phase_b_applicant_binding.sql
--     (fn_release_applicant_slot, fn_update_applicant_status §B6 — Phase B base)
--   20260813000001_wire_open_pipeline_slot_transitions.sql
--     (fn_sync_vacancy_slot_open_pipeline — Phase 6.1 base)
-- ============================================================
-- PROBLEM (OHM2026_0131):
--   fn_update_applicant_pipeline (SEAM 2 RPC — 20260828000000) was authored
--   after Phase B (20260817000000) and does NOT include the Phase B slot-sync
--   hook. As a result, when a terminal status (backout / rejected / failed) is
--   set via the pipeline update path, the bound plantilla slot stays in
--   'pipeline' instead of transitioning back to 'open'. This causes:
--
--   1. Add Applicant → Open: slot moves open → pipeline (correct — Phase B).
--   2. Backout / Reject / Failed via fn_update_applicant_pipeline → slot
--      stays pipeline (BUG — slot should return to open).
--   3. vw_slot_derived_vacancy_shadow shows stale pipeline_count > 0 even
--      when no active applicant exists → VCODE stays in Pipeline tab instead
--      of returning to Open tab.
--   4. Partial HC (HC=2, 1 terminal applicant): the freed slot stays pipeline;
--      vacancy_tab never re-derives as Open even though one slot is genuinely
--      available. (Once this fix is applied, Phase D Q4 priority naturally
--      handles partial HC correctly: open_count > 0 → Open.)
--
-- ROOT CAUSE:
--   fn_update_applicant_pipeline was written with the comment
--   "Does not mutate slots, CGCODE objects, or Plantilla lifecycle."
--   The "does not mutate slots" clause was intentional in SEAM 2's narrow
--   scope, but was never patched once Phase B landed. The Phase B pattern
--   (fn_update_applicant_status §B6) is the authoritative guide.
--
-- FIX:
--   Patch fn_update_applicant_pipeline — ONE ADDITION only.
--   After the main applicant UPDATE (and optional deployed-flag updates),
--   add the Phase B slot routing block, executed only when v_status_changed
--   is true and the new status is terminal:
--
--     bound applicant (slot_id IS NOT NULL) → fn_release_applicant_slot
--     unbound (slot_id IS NULL, roving, legacy) → fn_sync_vacancy_slot_open_pipeline
--
--   Both helpers are NON-BLOCKING (NEVER RAISE). A slot sync error will not
--   roll back this function's applicant write or history inserts.
--
-- SCOPE:
--   • Stationary non-roving VCODEs with plantilla_slots: slot transitions
--     correctly back to 'open' on terminal status. open_count becomes > 0,
--     vacancy_tab re-derives as 'Open' in vw_slot_derived_vacancy_shadow.
--   • Partial HC (HC=N): after the freed slot returns to 'open', Phase D Q4
--     priority (open_count > 0 → Open) keeps the VCODE in Open tab with the
--     correct count strip. No additional change needed.
--   • Roving VCODEs / unbound applicants: fn_sync_vacancy_slot_open_pipeline
--     is called (legacy path) — this is a no-op for roving (is_roving=true
--     guard) and harmless for VCODEs with no slot. The legacy vw_vacancy_list
--     already computes active_applicant_count from the applicants table
--     directly, so roving tab classification does not depend on slot state.
--
-- WHAT THIS MIGRATION DOES NOT DO:
--   • Does not change roving applicant sync across stores (roving multi-store
--     propagation remains deferred — OHM2026_0017 Q6 carve-out).
--   • Does not change create_applicant_and_link_to_vacancy (Phase B: correct).
--   • Does not change fn_update_applicant_status (Phase B §B6: correct).
--   • Does not change confirm_applicant_onboard (Phase 6.2: correct).
--   • Does not change move_to_plantilla (Phase 6.3: correct).
--   • Does not change the shadow view or any other migration.
--   • Does not touch the Flutter / Dart layer.
--   • Does not change RBAC, SEAM 2 history writes, or any other SEAM 2 behavior.
--
-- Sections:
--   §1  Patch fn_update_applicant_pipeline (add slot sync hook)
--   §2  GRANT (restore original SEAM 2 grants)
--   §3  Validation queries (manual)
-- ============================================================


-- ============================================================
-- §1  Patch fn_update_applicant_pipeline
-- ============================================================
-- Source: 20260828000000_applicant_pipeline_seam2_rpcs.sql §3.
-- Change: ONE addition — Phase B slot sync block inserted after the
--         deployed-flag UPDATE statements and before the history INSERTs.
-- All existing behavior — RBAC, change-count guard, main applicant UPDATE,
-- deployed_reliever/commando updates, history inserts, return shape,
-- SECURITY DEFINER, GRANT — is preserved IDENTICALLY.
-- No parameter or return type changes.
--
-- Slot sync routing (mirrors Phase B §B6, fn_update_applicant_status):
--   v_status_changed AND v_new_status.is_terminal = true:
--     v_app.slot_id IS NOT NULL → fn_release_applicant_slot (per-slot release)
--     v_app.slot_id IS NULL     → fn_sync_vacancy_slot_open_pipeline (legacy)
--   v_status_changed AND v_new_status.is_terminal = false:
--     no slot change (pipeline active → slot stays pipeline; Confirmed Onboard
--     stays pipeline until Phase 6.2 confirm_applicant_onboard fires).
--   NOT v_status_changed:
--     no slot change (follow_up / remarks / deployment flags only).

CREATE OR REPLACE FUNCTION public.fn_update_applicant_pipeline(
  p_applicant_id uuid,
  p_new_status text DEFAULT NULL,
  p_follow_up_date date DEFAULT NULL,
  p_recruitment_remarks text DEFAULT NULL,
  p_ops_remarks text DEFAULT NULL,
  p_deployed_reliever boolean DEFAULT NULL,
  p_deployed_commando boolean DEFAULT NULL,
  p_reason_id uuid DEFAULT NULL,
  p_reason_type text DEFAULT NULL,
  p_clear_recruitment_remarks boolean DEFAULT false,
  p_clear_ops_remarks boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level int := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_actor_name text;

  v_app record;
  v_old_status_code text;
  v_old_status_terminal boolean := false;
  v_new_status public.applicant_status_options%ROWTYPE;
  v_new_status_code text;
  v_new_status_label text;

  v_now timestamptz := now();
  v_history_ids uuid[] := ARRAY[]::uuid[];
  v_change_count int := 0;

  v_old_recruitment_remarks text;
  v_new_recruitment_remarks text;
  v_old_ops_remarks text;
  v_new_ops_remarks text;
  v_old_follow_up_date date;
  v_new_follow_up_date date;

  v_has_deployed_reliever boolean := false;
  v_has_deployed_commando boolean := false;
  v_old_deployed_reliever boolean;
  v_old_deployed_commando boolean;

  v_status_changed boolean := false;
  v_follow_up_changed boolean := false;
  v_recruitment_remarks_changed boolean := false;
  v_ops_remarks_changed boolean := false;
  v_deployed_reliever_changed boolean := false;
  v_deployed_commando_changed boolean := false;

  v_history_id uuid;
BEGIN
  IF v_level = 0 THEN
    RAISE EXCEPTION 'forbidden: authenticated user with a recognized role required'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason_type IS NOT NULL
     AND p_reason_type NOT IN ('backout', 'rejected', 'other') THEN
    RAISE EXCEPTION 'invalid reason_type: %. Must be backout | rejected | other', p_reason_type
      USING ERRCODE = '22023';
  END IF;

  IF p_new_status IS NULL
     AND p_follow_up_date IS NULL
     AND p_recruitment_remarks IS NULL
     AND p_ops_remarks IS NULL
     AND p_deployed_reliever IS NULL
     AND p_deployed_commando IS NULL
     AND NOT COALESCE(p_clear_recruitment_remarks, false)
     AND NOT COALESCE(p_clear_ops_remarks, false) THEN
    RAISE EXCEPTION 'no applicant pipeline changes requested'
      USING ERRCODE = '22023';
  END IF;

  -- Vacancy module lock is authoritative for applicant pipeline updates.
  PERFORM public.fn_assert_vacancy_edit_allowed_op('UPDATE');

  SELECT up.full_name
  INTO v_actor_name
  FROM public.users_profile up
  WHERE up.id = v_profile_id;

  SELECT *
  INTO v_app
  FROM public.applicants
  WHERE id = p_applicant_id
    AND COALESCE(is_archived, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- HA has full read visibility elsewhere but is explicitly read-only here.
  IF v_level = 90 THEN
    RAISE EXCEPTION 'Head Admin is read-only for applicant pipeline updates'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (v_level = 100 OR public.i_am_recruitment() OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'forbidden: applicant pipeline updates are limited to Recruitment, HRCO/ATL/TL/OM, and Super Admin'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.vacancies v
      WHERE v.vcode = v_app.vacancy_vcode
        AND v.account = ANY(public.get_my_allowed_accounts())
        AND v.deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT aso.status_code, aso.is_terminal
  INTO v_old_status_code, v_old_status_terminal
  FROM public.applicant_status_options aso
  WHERE aso.status_code = v_app.status
     OR aso.label = v_app.status
     OR lower(regexp_replace(aso.label, '[^a-zA-Z0-9]+', '_', 'g')) =
        lower(regexp_replace(COALESCE(v_app.status, ''), '[^a-zA-Z0-9]+', '_', 'g'))
  ORDER BY CASE WHEN aso.status_code = v_app.status THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_old_status_code IS NULL THEN
    v_old_status_code := lower(regexp_replace(COALESCE(v_app.status, ''), '[^a-zA-Z0-9]+', '_', 'g'));
    v_old_status_terminal := false;
  END IF;

  IF v_old_status_code = 'confirmed_onboard' AND v_level < 100 THEN
    RAISE EXCEPTION 'applicant is onboarded; only Super Admin may update applicant pipeline fields'
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(v_old_status_terminal, false) AND p_new_status IS NOT NULL AND v_level < 100 THEN
    RAISE EXCEPTION 'cannot change status from terminal status % without Super Admin override', v_app.status
      USING ERRCODE = '42501';
  END IF;

  IF (p_new_status IS NOT NULL OR p_follow_up_date IS NOT NULL)
     AND NOT (v_level = 100 OR public.i_am_recruitment() OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'only Recruitment, HRCO/ATL/TL/OM, or Super Admin may update status or follow_up_date'
      USING ERRCODE = '42501';
  END IF;

  IF (p_recruitment_remarks IS NOT NULL OR COALESCE(p_clear_recruitment_remarks, false))
     AND NOT (v_level = 100 OR public.i_am_recruitment()) THEN
    RAISE EXCEPTION 'only Recruitment or Super Admin may update recruitment_remarks'
      USING ERRCODE = '42501';
  END IF;

  IF (p_ops_remarks IS NOT NULL OR COALESCE(p_clear_ops_remarks, false))
     AND NOT (v_level = 100 OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'only HRCO/ATL/TL/OM or Super Admin may update ops_remarks'
      USING ERRCODE = '42501';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'applicants'
      AND column_name = 'deployed_reliever'
  )
  INTO v_has_deployed_reliever;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'applicants'
      AND column_name = 'deployed_commando'
  )
  INTO v_has_deployed_commando;

  IF p_deployed_reliever IS NOT NULL AND NOT v_has_deployed_reliever THEN
    RAISE EXCEPTION 'applicants.deployed_reliever is not available in this schema'
      USING ERRCODE = '42703';
  END IF;

  IF p_deployed_commando IS NOT NULL AND NOT v_has_deployed_commando THEN
    RAISE EXCEPTION 'applicants.deployed_commando is not available in this schema'
      USING ERRCODE = '42703';
  END IF;

  IF (p_deployed_reliever IS NOT NULL OR p_deployed_commando IS NOT NULL)
     AND NOT (v_level = 100 OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'only HRCO/ATL/TL/OM or Super Admin may update deployment flags'
      USING ERRCODE = '42501';
  END IF;

  IF p_new_status IS NOT NULL THEN
    v_new_status_code := lower(regexp_replace(btrim(p_new_status), '[^a-zA-Z0-9]+', '_', 'g'));

    SELECT *
    INTO v_new_status
    FROM public.applicant_status_options aso
    WHERE aso.is_active = true
      AND (
        aso.status_code = p_new_status
        OR aso.status_code = v_new_status_code
        OR aso.label = p_new_status
      )
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'unknown or inactive applicant status: %', p_new_status
        USING ERRCODE = '22023';
    END IF;

    IF v_new_status.is_system_only AND v_level < 100 THEN
      RAISE EXCEPTION 'status % is system-managed and cannot be set manually', v_new_status.status_code
        USING ERRCODE = '42501';
    END IF;

    IF v_new_status.status_code = 'new'
       AND COALESCE(v_old_status_code, '') <> 'new'
       AND v_level < 100 THEN
      RAISE EXCEPTION 'return to Sourcing is blocked; Super Admin override required'
        USING ERRCODE = '42501';
    END IF;

    v_new_status_label := v_new_status.label;
    v_status_changed := v_new_status_label IS DISTINCT FROM v_app.status;
  END IF;

  v_old_follow_up_date := v_app.follow_up_date;
  v_new_follow_up_date := COALESCE(p_follow_up_date, v_old_follow_up_date);
  v_follow_up_changed := p_follow_up_date IS NOT NULL
    AND v_new_follow_up_date IS DISTINCT FROM v_old_follow_up_date;

  v_old_recruitment_remarks := v_app.recruitment_remarks;
  IF COALESCE(p_clear_recruitment_remarks, false) THEN
    v_new_recruitment_remarks := NULL;
    v_recruitment_remarks_changed := v_old_recruitment_remarks IS NOT NULL;
  ELSIF p_recruitment_remarks IS NOT NULL THEN
    v_new_recruitment_remarks := p_recruitment_remarks;
    v_recruitment_remarks_changed := v_new_recruitment_remarks IS DISTINCT FROM v_old_recruitment_remarks;
  ELSE
    v_new_recruitment_remarks := v_old_recruitment_remarks;
  END IF;

  v_old_ops_remarks := v_app.ops_remarks;
  IF COALESCE(p_clear_ops_remarks, false) THEN
    v_new_ops_remarks := NULL;
    v_ops_remarks_changed := v_old_ops_remarks IS NOT NULL;
  ELSIF p_ops_remarks IS NOT NULL THEN
    v_new_ops_remarks := p_ops_remarks;
    v_ops_remarks_changed := v_new_ops_remarks IS DISTINCT FROM v_old_ops_remarks;
  ELSE
    v_new_ops_remarks := v_old_ops_remarks;
  END IF;

  IF v_has_deployed_reliever THEN
    v_old_deployed_reliever := (to_jsonb(v_app)->>'deployed_reliever')::boolean;
    v_deployed_reliever_changed := p_deployed_reliever IS NOT NULL
      AND p_deployed_reliever IS DISTINCT FROM v_old_deployed_reliever;
  END IF;

  IF v_has_deployed_commando THEN
    v_old_deployed_commando := (to_jsonb(v_app)->>'deployed_commando')::boolean;
    v_deployed_commando_changed := p_deployed_commando IS NOT NULL
      AND p_deployed_commando IS DISTINCT FROM v_old_deployed_commando;
  END IF;

  v_change_count :=
    CASE WHEN v_status_changed THEN 1 ELSE 0 END +
    CASE WHEN v_follow_up_changed THEN 1 ELSE 0 END +
    CASE WHEN v_recruitment_remarks_changed THEN 1 ELSE 0 END +
    CASE WHEN v_ops_remarks_changed THEN 1 ELSE 0 END +
    CASE WHEN v_deployed_reliever_changed THEN 1 ELSE 0 END +
    CASE WHEN v_deployed_commando_changed THEN 1 ELSE 0 END;

  IF v_change_count = 0 THEN
    RAISE EXCEPTION 'no applicant pipeline field values changed'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.applicants
  SET status = CASE WHEN v_status_changed THEN v_new_status_label ELSE status END,
      follow_up_date = CASE WHEN v_follow_up_changed THEN v_new_follow_up_date ELSE follow_up_date END,
      recruitment_remarks = CASE
        WHEN v_recruitment_remarks_changed THEN v_new_recruitment_remarks
        ELSE recruitment_remarks
      END,
      ops_remarks = CASE
        WHEN v_ops_remarks_changed THEN v_new_ops_remarks
        ELSE ops_remarks
      END,
      last_activity_at = v_now,
      last_activity_by = v_profile_id,
      last_activity_by_name = v_actor_name,
      updated_at = v_now,
      updated_by = v_profile_id
  WHERE id = p_applicant_id;

  IF v_deployed_reliever_changed THEN
    EXECUTE 'UPDATE public.applicants SET deployed_reliever = $1 WHERE id = $2'
    USING p_deployed_reliever, p_applicant_id;
  END IF;

  IF v_deployed_commando_changed THEN
    EXECUTE 'UPDATE public.applicants SET deployed_commando = $1 WHERE id = $2'
    USING p_deployed_commando, p_applicant_id;
  END IF;

  -- ── OHM2026_0131: Phase B slot sync hook ─────────────────────────────────
  -- Mirrors fn_update_applicant_status §B6 (Phase B, OHM2026_0041).
  -- Only executes when a terminal status was applied (backout/rejected/failed).
  -- Non-terminal status changes (active→active, active→confirmed_onboard, etc.)
  -- do not move the slot — slot stays 'pipeline'; Phase 6.2 handles the
  -- pipeline→hr_processing transition on confirm_applicant_onboard.
  --
  -- Routing:
  --   slot_id IS NOT NULL (bound applicant, stationary non-roving slot):
  --     → fn_release_applicant_slot: if no other active applicant remains
  --       on the slot, transitions pipeline → open (aging episode restarts).
  --   slot_id IS NULL (unbound: roving, legacy no-slot VCODE, or unbackfilled):
  --     → fn_sync_vacancy_slot_open_pipeline: counts active applicants and
  --       transitions open↔pipeline. No-op for roving (is_roving=true guard)
  --       and for VCODEs with no slot (slot lookup returns NULL).
  --
  -- Both helpers NEVER RAISE. A slot sync error logs via RAISE NOTICE and
  -- does NOT roll back this function's applicant write or history inserts.
  IF v_status_changed AND COALESCE(v_new_status.is_terminal, false) THEN
    IF v_app.slot_id IS NOT NULL THEN
      PERFORM public.fn_release_applicant_slot(
        p_slot_id      => v_app.slot_id,
        p_performed_by => v_profile_id
      );
    ELSE
      PERFORM public.fn_sync_vacancy_slot_open_pipeline(
        p_vcode        => v_app.vacancy_vcode,
        p_performed_by => v_profile_id,
        p_source_fn    => 'fn_update_applicant_pipeline'
      );
    END IF;
  END IF;
  -- ─────────────────────────────────────────────────────────────────────────

  IF v_status_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, changed_by_name
    ) VALUES (
      v_history_id, p_applicant_id, v_app.status, v_new_status_label,
      p_reason_id, p_reason_type, NULL, v_profile_id, v_now, 'vacancy',
      'status_change', 'status', v_app.status, v_new_status_label, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
  END IF;

  IF v_follow_up_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_follow_up_date, new_follow_up_date,
      changed_by_name
    ) VALUES (
      v_history_id, p_applicant_id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'follow_up_update',
      'follow_up_date', v_old_follow_up_date::text, v_new_follow_up_date::text,
      v_old_follow_up_date, v_new_follow_up_date, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
  END IF;

  IF v_recruitment_remarks_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_recruitment_remarks,
      new_recruitment_remarks, changed_by_name
    ) VALUES (
      v_history_id, p_applicant_id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'recruitment_remarks_update',
      'recruitment_remarks', v_old_recruitment_remarks, v_new_recruitment_remarks,
      v_old_recruitment_remarks, v_new_recruitment_remarks, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
  END IF;

  IF v_ops_remarks_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_ops_remarks, new_ops_remarks,
      changed_by_name
    ) VALUES (
      v_history_id, p_applicant_id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'ops_remarks_update',
      'ops_remarks', v_old_ops_remarks, v_new_ops_remarks,
      v_old_ops_remarks, v_new_ops_remarks, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
  END IF;

  IF v_deployed_reliever_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_deployed_reliever,
      new_deployed_reliever, changed_by_name
    ) VALUES (
      v_history_id, p_applicant_id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'deployed_reliever_update',
      'deployed_reliever', v_old_deployed_reliever::text, p_deployed_reliever::text,
      v_old_deployed_reliever, p_deployed_reliever, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
  END IF;

  IF v_deployed_commando_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_deployed_commando,
      new_deployed_commando, changed_by_name
    ) VALUES (
      v_history_id, p_applicant_id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'deployed_commando_update',
      'deployed_commando', v_old_deployed_commando::text, p_deployed_commando::text,
      v_old_deployed_commando, p_deployed_commando, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'applicant_id', p_applicant_id,
    'updated_status', CASE WHEN v_status_changed THEN v_new_status_label ELSE v_app.status END,
    'last_activity_at', v_now,
    'last_activity_by', v_profile_id,
    'last_activity_by_name', v_actor_name,
    'history_ids', to_jsonb(v_history_ids),
    'changed_fields', (
      SELECT jsonb_agg(x.field_name ORDER BY x.sort_order)
      FROM (
        VALUES
          (1, 'status', v_status_changed),
          (2, 'follow_up_date', v_follow_up_changed),
          (3, 'recruitment_remarks', v_recruitment_remarks_changed),
          (4, 'ops_remarks', v_ops_remarks_changed),
          (5, 'deployed_reliever', v_deployed_reliever_changed),
          (6, 'deployed_commando', v_deployed_commando_changed)
      ) AS x(sort_order, field_name, changed)
      WHERE x.changed
    )
  );
END;
$$;

COMMENT ON FUNCTION public.fn_update_applicant_pipeline(
  uuid, text, date, text, text, boolean, boolean, uuid, text, boolean, boolean
) IS
  'SEAM 2 manual applicant pipeline update RPC. Stores UTC timestamptz, writes one '
  'applicant_status_history row per changed field, enforces Recruitment/Ops ownership, '
  'HA read-only, onboard lock, terminal source lock, and Sourcing return block. '
  'OHM2026_0131: adds Phase B slot sync hook — terminal status transitions call '
  'fn_release_applicant_slot (bound slot_id) or fn_sync_vacancy_slot_open_pipeline '
  '(unbound/roving/legacy), both non-blocking. Non-terminal status changes do not '
  'modify slot state.';


-- ============================================================
-- §2  GRANT (restore original SEAM 2 grants — unchanged)
-- ============================================================

REVOKE ALL ON FUNCTION public.fn_update_applicant_pipeline(
  uuid, text, date, text, text, boolean, boolean, uuid, text, boolean, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_update_applicant_pipeline(
  uuid, text, date, text, text, boolean, boolean, uuid, text, boolean, boolean
) TO authenticated, service_role;


-- ============================================================
-- §3  Validation queries (run manually after applying)
-- ============================================================
--
-- V1 — Function body includes OHM2026_0131 slot sync hook
--   SELECT prosrc LIKE '%fn_release_applicant_slot%'
--     AND prosrc LIKE '%fn_sync_vacancy_slot_open_pipeline%'
--   FROM pg_proc
--   WHERE proname = 'fn_update_applicant_pipeline'
--     AND pronamespace = 'public'::regnamespace;
--   -- Expected: true
--
-- V2 — Terminal status (backout) transitions bound slot pipeline → open
--   -- Precondition: VCODE with 1 open slot, add 1 applicant (slot becomes pipeline)
--   SELECT slot_status FROM public.plantilla_slots
--   WHERE legacy_vcode = '<test_vcode>';
--   -- Expected: 'pipeline'
--
--   -- Set applicant to backout via fn_update_applicant_pipeline:
--   SELECT public.fn_update_applicant_pipeline(
--     p_applicant_id => '<applicant_uuid>',
--     p_new_status   => 'backout',
--     p_reason_type  => 'backout'
--   );
--
--   SELECT slot_status FROM public.plantilla_slots
--   WHERE legacy_vcode = '<test_vcode>';
--   -- Expected: 'open' (slot released back to open)
--
--   SELECT action_type, old_value, new_value, remarks
--   FROM public.slot_history
--   WHERE slot_id = (SELECT id FROM public.plantilla_slots WHERE legacy_vcode = '<test_vcode>')
--   ORDER BY created_at DESC LIMIT 3;
--   -- Expected: most recent row action_type='reopened', old_value='pipeline', new_value='open'
--   --           remarks includes 'Phase B release / last active applicant went terminal'
--
-- V3 — Partial HC (HC=2): 1 backout frees 1 slot; VCODE returns to Open tab
--   -- Precondition: VCODE with HC=2 (2 slots), 2 active applicants (both pipeline)
--   SELECT open_count, pipeline_count, vacancy_tab
--   FROM public.vw_slot_derived_vacancy_shadow
--   WHERE legacy_vcode = '<test_vcode>';
--   -- Pre-fix expected: open=0, pipeline=2, tab='Pipeline'
--
--   -- Backout one applicant:
--   SELECT public.fn_update_applicant_pipeline(
--     p_applicant_id => '<applicant_1_uuid>',
--     p_new_status   => 'backout',
--     p_reason_type  => 'backout'
--   );
--
--   SELECT open_count, pipeline_count, vacancy_tab
--   FROM public.vw_slot_derived_vacancy_shadow
--   WHERE legacy_vcode = '<test_vcode>';
--   -- Expected: open=1, pipeline=1, vacancy_tab='Open'
--   -- (Phase D Q4 P2: open_count > 0 → Open takes priority over Pipeline)
--
-- V4 — Non-terminal status change does not alter slot state
--   -- Precondition: slot in 'pipeline'
--   SELECT slot_status FROM public.plantilla_slots WHERE legacy_vcode = '<test_vcode>';
--   -- Expected: 'pipeline'
--
--   -- Update follow-up date or remarks (no status change):
--   SELECT public.fn_update_applicant_pipeline(
--     p_applicant_id   => '<applicant_uuid>',
--     p_follow_up_date => CURRENT_DATE + 3
--   );
--
--   SELECT slot_status FROM public.plantilla_slots WHERE legacy_vcode = '<test_vcode>';
--   -- Expected: 'pipeline' (unchanged)
--
-- V5 — Active status change (New → For Interview) does not alter slot state
--   SELECT public.fn_update_applicant_pipeline(
--     p_applicant_id => '<applicant_uuid>',
--     p_new_status   => 'for_interview'
--   );
--   SELECT slot_status FROM public.plantilla_slots WHERE legacy_vcode = '<test_vcode>';
--   -- Expected: 'pipeline' (unchanged; slot stays pipeline for active transitions)
--
-- V6 — Roving applicant (slot_id IS NULL) backout: legacy sync path fires
--   -- For a roving vacancy applicant with slot_id IS NULL:
--   -- fn_sync_vacancy_slot_open_pipeline is called but skips due to is_roving=true guard.
--   -- No slot_history row is written (roving excluded by design).
--   -- Legacy vw_vacancy_list active_applicant_count updates via direct applicant count.
--   SELECT count(*) FROM public.slot_history
--   WHERE remarks LIKE '%fn_update_applicant_pipeline%'
--     AND (
--       SELECT slot_id FROM public.applicants WHERE id = '<roving_applicant_uuid>'
--     ) IS NULL;
--   -- Expected: no slot_history rows written for this roving applicant's vcode
--
-- V7 — Add applicant (open → pipeline) still works correctly after this patch
--   -- fn is unchanged; Phase B create_applicant_and_link_to_vacancy still runs
--   -- the validated slot claim path. This migration does not alter that function.
--   SELECT slot_status FROM public.plantilla_slots WHERE legacy_vcode = '<test_vcode>';
--   -- After adding first applicant: Expected 'pipeline'
--
-- V8 — Function signature unchanged (SEAM 2 11-argument signature preserved)
--   SELECT proname, pg_get_function_arguments(oid) AS args
--   FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace
--     AND proname = 'fn_update_applicant_pipeline';
--   -- Expected: one row with 11-argument signature identical to SEAM 2 migration
--
-- V9 — Existing SEAM 2 behavior unchanged: RBAC, history writes, return shape
--   -- Run existing SEAM 2 V6/V7/V8/V9 validation tests; expected results unchanged.
-- ============================================================
