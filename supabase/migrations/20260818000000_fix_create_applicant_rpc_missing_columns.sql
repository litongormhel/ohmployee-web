-- ============================================================
-- OHM2026_0043 — Fix create_applicant_and_link_to_vacancy: remove non-existent column refs
-- Migration: 20260818000000_fix_create_applicant_rpc_missing_columns.sql
-- Depends on:
--   20260817000000_vcode_slot_phase_b_applicant_binding.sql (Phase B — applied)
-- ============================================================
-- Root cause:
--   The Phase B (20260817000000) replacement of create_applicant_and_link_to_vacancy
--   kept the INSERT column list from the Phase 6.1 base unchanged. That base referenced
--   four columns that do not exist in public.applicants:
--     • application_date   — never added to the table
--     • source_channel     — never added to the table (lookup is applicant_source_channels)
--     • comment            — never added to the table
--     • master_applicant_id — lives in roving_assignments, not applicants
--   This caused a column-not-found error at runtime for any client call that passes
--   i_am_ops(). The slot-claim and fn_set_slot_status logic was unreachable.
--
-- Fix:
--   Remove application_date, source_channel, comment from INSERT column list + VALUES.
--   Remove the UPDATE … SET master_applicant_id statement.
--   Function signature is preserved (p_application_date, p_source_channel, p_comment
--   remain as parameters — removing them would break existing callers; the DB silently
--   accepts extra positional/named params that are received but not used in the body).
--   All Phase B slot-claim logic (slot count, FOR UPDATE SKIP LOCKED, fn_set_slot_status,
--   legacy fn_sync_vacancy_slot_open_pipeline path) is IDENTICAL to Phase B.
--
-- Columns removed from INSERT:
--   application_date   — removed (column does not exist in public.applicants)
--   source_channel     — removed (column does not exist in public.applicants)
--   comment            — removed (column does not exist in public.applicants)
--
-- UPDATE removed:
--   UPDATE public.applicants SET master_applicant_id = new_id WHERE id = new_id;
--   (master_applicant_id does not exist in public.applicants; it belongs to roving_assignments)
--
-- Phase B slot primitives NOT changed:
--   fn_release_applicant_slot — unchanged
--   fn_update_applicant_status — unchanged
--   uq_applicants_one_active_per_slot index — unchanged
--   fn_set_slot_status calls — unchanged
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_applicant_and_link_to_vacancy(
  p_vacancy_id      uuid,
  p_last_name       text,
  p_first_name      text,
  p_middle_name     text,
  p_contact_number  text,
  p_application_date date,
  p_source_channel  text DEFAULT 'Walk-in',
  p_comment         text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
/*
  OHM2026_0043 — Patched: removed application_date, source_channel, comment,
  master_applicant_id from INSERT (columns do not exist in public.applicants).
  Phase B slot-claim logic (§B5) is identical to 20260817000000.
*/
DECLARE
  v              public.vacancies%ROWTYPE;
  new_id         uuid;
  v_claimed_slot uuid;
  v_claimed_ord  smallint;
  v_slot_count   bigint;
  v_slot_result  jsonb;
BEGIN
  IF NOT public.i_am_ops() THEN
    RAISE EXCEPTION 'forbidden: ops only';
  END IF;

  -- Required-field guard
  IF p_last_name IS NULL OR p_first_name IS NULL OR p_middle_name IS NULL
     OR p_contact_number IS NULL THEN
    RAISE EXCEPTION 'last_name, first_name, middle_name, contact_number are required';
  END IF;

  -- Format guard
  PERFORM public.fn_validate_ph_contact_number(p_contact_number);

  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'vacancy not found'; END IF;
  IF v.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'vacancy archived'; END IF;
  IF COALESCE(v.has_pending_closure, false) THEN
    RAISE EXCEPTION 'vacancy is locked pending deletion';
  END IF;
  IF NOT (v.account = ANY (public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: out of scope';
  END IF;

  -- ── Phase B: slot-aware claim ─────────────────────────────────────────────
  -- Count non-roving slots for this VCODE (roving skipped — carve-out).
  SELECT COUNT(*) INTO v_slot_count
  FROM   public.plantilla_slots
  WHERE  legacy_vcode = v.vcode
    AND  is_roving    = false;

  IF v_slot_count > 0 THEN
    -- VCODE has slots — claim the lowest available open slot.
    -- FOR UPDATE SKIP LOCKED: concurrent adds take different slots instead
    -- of colliding; uq_applicants_one_active_per_slot is the backstop.
    SELECT id, slot_ordinal
      INTO v_claimed_slot, v_claimed_ord
    FROM   public.plantilla_slots
    WHERE  legacy_vcode = v.vcode
      AND  slot_status  = 'open'
      AND  is_roving    = false
    ORDER  BY slot_ordinal ASC, created_at ASC, id ASC
    LIMIT  1
    FOR UPDATE SKIP LOCKED;

    IF v_claimed_slot IS NULL THEN
      -- All slots are occupied/pipeline/hr_processing/closed — hard reject.
      RAISE EXCEPTION
        'no_open_slot: VCODE % has % slot(s) but none are open. '
        'All headcount is in pipeline, processing, filled, or closed. '
        'Request additional HC before adding another applicant.',
        v.vcode, v_slot_count
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  -- If v_slot_count = 0: v_claimed_slot stays NULL → legacy path below.
  -- ─────────────────────────────────────────────────────────────────────────

  INSERT INTO public.applicants (
    vacancy_vcode, last_name, first_name, middle_name, full_name,
    contact_number, status, slot_id, created_by
  ) VALUES (
    v.vcode, p_last_name, p_first_name, p_middle_name,
    p_last_name || ', ' || p_first_name || ' ' || p_middle_name,
    p_contact_number,
    'New', v_claimed_slot, public.get_my_profile_id()
  ) RETURNING id INTO new_id;

  PERFORM public.log_audit_event(
    'vacancy_module', 'INSERT', new_id,
    NULL,
    jsonb_build_object('action', 'create_applicant', 'vacancy_id', v.id)
  );

  -- ── Phase B: slot status transition ──────────────────────────────────────
  IF v_claimed_slot IS NOT NULL THEN
    -- Slot-aware path: direct open → pipeline transition for the claimed slot.
    -- This is a validated (blocking) call — if the transition is unexpectedly
    -- blocked the insert rolls back, surfacing a data integrity issue.
    SELECT public.fn_set_slot_status(
      p_slot_id      => v_claimed_slot,
      p_new_status   => 'pipeline',
      p_reason_code  => NULL,
      p_performed_by => public.get_my_profile_id(),
      p_remarks      => format(
        'Phase B / create_applicant_and_link_to_vacancy / VCODE=%s / '
        'applicant=%s / slot_ordinal=%s',
        v.vcode, new_id, v_claimed_ord
      )
    ) INTO v_slot_result;

    IF (v_slot_result->>'status') = 'blocked' THEN
      RAISE EXCEPTION
        'slot_transition_blocked: claimed slot % could not transition to '
        'pipeline — %. This indicates a data integrity issue; resolve '
        'slot status before adding applicants.',
        v_claimed_slot, v_slot_result->>'blocked_reason'
        USING ERRCODE = 'P0001';
    END IF;
  ELSE
    -- No slots for this VCODE — legacy non-blocking sync (no-op if no slot).
    PERFORM public.fn_sync_vacancy_slot_open_pipeline(
      p_vcode        => v.vcode,
      p_performed_by => public.get_my_profile_id(),
      p_source_fn    => 'create_applicant_and_link_to_vacancy'
    );
  END IF;
  -- ─────────────────────────────────────────────────────────────────────────

  RETURN new_id;
END;
$$;

COMMENT ON FUNCTION public.create_applicant_and_link_to_vacancy(uuid, text, text, text, text, date, text, text) IS
  'Creates and links a new applicant to a vacancy. '
  'OHM2026_0043: patched to remove non-existent INSERT columns (application_date, '
  'source_channel, comment, master_applicant_id). Function signature unchanged. '
  'Phase B (OHM2026_0041): claims the lowest open non-roving slot for the VCODE '
  'before INSERT (FOR UPDATE SKIP LOCKED); binds applicants.slot_id; transitions '
  'the claimed slot open→pipeline via fn_set_slot_status. '
  'Rejects (SQLSTATE P0001) if the VCODE has slots but none are open. '
  'VCODEs with no slots use the legacy fn_sync_vacancy_slot_open_pipeline path. '
  'Roving slots are skipped (legacy path).';


-- ============================================================
-- GRANTs — unchanged from Phase B
-- ============================================================
-- create_applicant_and_link_to_vacancy: inherited from remote_schema; no change.


-- ============================================================
-- Post-patch validation queries (run manually)
-- ============================================================
--
-- C1 — Function body no longer references missing columns.
--   SELECT prosrc
--     FROM pg_proc
--     WHERE proname      = 'create_applicant_and_link_to_vacancy'
--       AND pronamespace = 'public'::regnamespace;
--   -- Expected: body does NOT contain 'application_date', 'source_channel',
--   --           'comment', 'master_applicant_id' in the INSERT block.
--
-- C2 — Add Applicant smoke test (slot-aware VCODE).
--   SELECT public.create_applicant_and_link_to_vacancy(
--     p_vacancy_id      => '<vacancy_uuid_with_open_slot>',
--     p_last_name       => 'TestLast',
--     p_first_name      => 'TestFirst',
--     p_middle_name     => 'T',
--     p_contact_number  => '09171234567',
--     p_application_date => CURRENT_DATE
--   );
--   -- Expected: returns uuid (new applicant id), no column-not-found error.
--
-- C3 — New applicant has non-NULL slot_id.
--   SELECT slot_id FROM public.applicants WHERE id = '<result_from_C2>';
--   -- Expected: non-NULL uuid (the claimed slot).
--
-- C4 — Slot transitioned open → pipeline.
--   SELECT slot_status FROM public.plantilla_slots WHERE id = (
--     SELECT slot_id FROM public.applicants WHERE id = '<result_from_C2>'
--   );
--   -- Expected: 'pipeline'.
--
-- C5 — Legacy no-slot path still works.
--   SELECT public.create_applicant_and_link_to_vacancy(
--     p_vacancy_id      => '<vacancy_uuid_with_no_slots>',
--     p_last_name       => 'LegacyLast',
--     p_first_name      => 'LegacyFirst',
--     p_middle_name     => 'L',
--     p_contact_number  => '09179999999',
--     p_application_date => CURRENT_DATE
--   );
--   -- Expected: returns uuid, slot_id IS NULL on the new applicant row.
-- ============================================================
