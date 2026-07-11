-- ============================================================================
-- Fix: fn_sync_vacancy_slot_open_pipeline requests occupied->open on a slot
-- that is genuinely occupied by a hired employee.
-- Migration: 20260709060413_fix_sync_vacancy_slot_open_pipeline_occupied_guard.sql
-- Task: ohm#4dh6y1sc (BUG 2)
-- ============================================================================
-- PROBLEM:
--   fn_sync_vacancy_slot_open_pipeline() (called from fn_update_applicant_pipeline
--   on every applicant status write sharing a vacancy's VCODE) computes the
--   target slot status purely from COUNT(*) of applicants in "active"
--   statuses per fn_is_active_vacancy_applicant_status(), which excludes both
--   'confirmed_onboard' and 'backout'. When a winning applicant reaches
--   Confirmed Onboard and a losing co-applicant reaches Backout on the same
--   VCODE, the active count drops to 0 and the function requests
--   slot_status='open' via fn_set_slot_status() -- even though the slot is
--   genuinely occupied by the just-hired employee.
--
--   fn_set_slot_status()'s transition matrix correctly ALLOWS occupied->open
--   for its other, legitimate caller (the real separation trigger), so it does
--   not itself block this call -- the bug is that
--   fn_sync_vacancy_slot_open_pipeline has no business requesting that
--   transition at all. Per its own doc comment it is meant to be a
--   "non-blocking open<->pipeline slot sync" -- it should never touch a slot
--   that is already 'occupied'.
--
--   Confirmed live: slot dd67b8d8-9cb3-4a37-892b-f1e416298b0b (VCAG2_0024,
--   SM Bagulin) was flipped occupied->open at 2026-07-09 03:29:48 via
--   exactly this path (slot_history remarks: "Phase 6.1 /
--   fn_update_applicant_pipeline / VCODE=VCAG2_0024 / active_applicants=0"),
--   even though plantilla_id a792053c-96e9-4975-981c-7b4e5ed3f52a (the hired
--   employee) was still Active. System-wide scan found this is the only
--   occurrence on staging (no other slot_history row matches
--   action_type='resigned' + remarks ILIKE '%fn_update_applicant_pipeline%').
--
-- FIX:
--   Guard added immediately after the slot lookup, before the active-
--   applicant count / fn_set_slot_status call: if the slot's current
--   slot_status is already 'occupied', no-op and return NULL. This sync path
--   now only ever acts on slots still in 'open' or 'pipeline' state, matching
--   its own documented scope.
--
-- DATA CORRECTION (not part of this migration -- applied separately via
-- execute_sql per DATABASE CHANGE POLICY "Emergency Data Repairs": one-time,
-- data-only, does not belong in schema history):
--   slot dd67b8d8-9cb3-4a37-892b-f1e416298b0b restored to slot_status=
--   'occupied', current_occupant_plantilla_id=a792053c-96e9-4975-981c-
--   7b4e5ed3f52a via fn_set_slot_status(..., 'occupied', ..., p_occupant_
--   plantilla_id => ...). No duplicate Vacancy row was found for VCAG2_0024
--   (only one vacancy row exists, status Open, required_headcount 2.0000,
--   unaffected by this bug) -- so no vacancy archive/close action was needed.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_sync_vacancy_slot_open_pipeline(p_vcode text, p_performed_by uuid DEFAULT NULL::uuid, p_source_fn text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
/*
  Phase 6.1 — non-blocking open↔pipeline slot sync (OHM2026_0019).

  Active-applicant predicate mirrors vw_vacancy_list:
    fn_is_active_vacancy_applicant_status → new, for_interview,
    for_requirements, for_onboard.

  Reason code is NULL for both open→pipeline and pipeline→open:
  these transitions have no matching reason code in the design matrix
  (slot_lifecycle_automation_plan.md Q2/Q3 — "(none)").
  Context is fully captured in p_remarks via source function + VCODE + count.

  ohm#4dh6y1sc (BUG 2): this sync path must never request a transition off
  an 'occupied' slot -- occupied means a hired employee genuinely holds the
  slot, and only the real separation trigger (fn_plantilla_separation_to_vacancy)
  is allowed to move it off occupied. Guarded immediately below.
*/
DECLARE
  v_slot_id     uuid;
  v_slot_status text;
  v_active_cnt  bigint;
  v_target      text;
  v_result      jsonb;
BEGIN
  -- ── Guard: VCODE required ───────────────────────────────────────
  IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
    RAISE NOTICE
      'fn_sync_vacancy_slot_open_pipeline: skipped — p_vcode is null/empty (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- ── Locate slot via legacy_vcode bridge ──────────────────────────
  -- Partial-unique index on legacy_vcode guarantees at most one match.
  -- Roving slots excluded: no reliable 1:1 VCODE→slot until coverage model.
  SELECT id, slot_status INTO v_slot_id, v_slot_status
  FROM public.plantilla_slots
  WHERE legacy_vcode = p_vcode
    AND is_roving = false
  LIMIT 1;

  IF v_slot_id IS NULL THEN
    -- No slot for this VCODE (pre-slot-era legacy vacancy or roving) — skip.
    RETURN NULL;
  END IF;

  -- ── ohm#4dh6y1sc (BUG 2): occupied slots are out of scope for this sync ──
  -- A slot in 'occupied' status is held by a real hired employee. This
  -- non-blocking open<->pipeline sync must never request occupied->open
  -- (or any other transition) on it — only the separation trigger may move
  -- an occupied slot. Without this guard, a winning applicant reaching
  -- Confirmed Onboard + a losing co-applicant reaching Backout on the same
  -- VCODE drops the active-applicant count to 0 and wrongfully reopens the
  -- slot out from under the just-hired employee.
  IF v_slot_status = 'occupied' THEN
    RAISE NOTICE
      'fn_sync_vacancy_slot_open_pipeline: skipped — slot % is occupied, out of scope for this sync (VCODE=%, source=%)',
      v_slot_id, p_vcode, COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- ── Count active applicants for this VCODE (post-host-write) ────
  SELECT count(*) INTO v_active_cnt
  FROM public.applicants
  WHERE vacancy_vcode = p_vcode
    AND public.fn_is_active_vacancy_applicant_status(status)
    AND COALESCE(is_archived, false) = false;

  -- ── Derive target slot status ────────────────────────────────────
  v_target := CASE WHEN v_active_cnt > 0 THEN 'pipeline' ELSE 'open' END;

  -- ── Delegate to central transition helper ───────────────────────
  -- fn_set_slot_status handles: same-state no-op, matrix validation,
  -- slot row update (slot_status + updated_at/by), and slot_history append.
  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => v_target,
    p_reason_code           => NULL,
    p_performed_by          => p_performed_by,
    p_remarks               => format(
                                 'Phase 6.1 / %s / VCODE=%s / active_applicants=%s',
                                 COALESCE(p_source_fn, 'unknown'),
                                 p_vcode,
                                 v_active_cnt
                               ),
    p_occupant_plantilla_id => NULL
  ) INTO v_result;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  -- Non-blocking contract: log and skip. Host RPC transaction continues.
  RAISE NOTICE
    'fn_sync_vacancy_slot_open_pipeline: error for VCODE=% source=% — % (sqlstate=%)',
    p_vcode, COALESCE(p_source_fn, 'unknown'), SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$function$
;
