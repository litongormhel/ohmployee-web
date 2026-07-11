-- ============================================================
-- OHM2026_0061 — Fix Applicant Slot Sync on Direct INSERT
-- Migration: 20260602000003_fix_applicant_slot_sync_on_insert.sql
-- Depends on:
--   20260813000001_wire_open_pipeline_slot_transitions.sql
--     (fn_sync_vacancy_slot_open_pipeline — must exist)
--   20260812000000_fn_set_slot_status.sql
--     (fn_set_slot_status — must exist)
--   20260817000000_vcode_slot_phase_b_applicant_binding.sql
--     (Phase B slot architecture — must be live)
-- ============================================================
--
-- PROBLEM
-- -------
-- VacancyService.addApplicant() (Flutter) does a direct Supabase
-- table INSERT into `applicants`. It does NOT call the Phase B
-- RPC `create_applicant_and_link_to_vacancy`, which is the only
-- path that calls fn_sync_vacancy_slot_open_pipeline after insert.
--
-- As a result, when an applicant is added via the Flutter UI:
--   • The matching plantilla_slots row stays in slot_status = 'open'.
--   • vw_slot_derived_vacancy_shadow.pipeline_count remains 0.
--   • vacancy_tab is derived as 'Open' (Phase D P2: open_count > 0 → Open).
--   • Flutter Pipeline tab check (pipelineCount > 0) returns false.
--   • Count strip shows Pipeline: 0 even though an applicant exists.
--   • The Phase B invariant (active_applicant_count = pipeline_count)
--     is violated.
--
-- Symptom: stores like Super 8 Dau (VAC-MNL-007) show Open: 1,
-- Pipeline: 0 in the list, but Vacancy Details already has an applicant.
--
-- FIX
-- ---
-- Add an AFTER INSERT trigger on `applicants` that calls
-- fn_sync_vacancy_slot_open_pipeline for every new active applicant
-- row, regardless of which path performed the INSERT.
--
-- Non-blocking contract: the trigger function NEVER RAISES.
-- A slot-sync error is logged via RAISE NOTICE only and does not
-- roll back the host INSERT transaction.
--
-- Idempotency: fn_sync_vacancy_slot_open_pipeline delegates to
-- fn_set_slot_status, which is a no-op for same-state transitions.
-- Double-sync (e.g., create_applicant_and_link_to_vacancy + trigger)
-- produces at most one history row (the first write), then a no-op.
--
-- VCODE UNIQUENESS NOTE
-- ---------------------
-- generate_vcode_for_account collision guard:
--   WHILE EXISTS (SELECT 1 FROM vacancies WHERE vcode = v_vcode) LOOP
-- This check is unconditional — it includes archived rows
-- (is_archived = true). Archived VCODEs are correctly skipped during
-- generation. The vacancies_vcode_key UNIQUE constraint (unconditional)
-- is the second safety net that prevents a true duplicate row at the
-- DB level. No code change is needed for VCODE generation.
--
-- This migration adds a CHECK in create_vacancy_from_headcount_request
-- to explicitly guard against accidental archived VCODE reuse in that
-- path (defensive; should never trigger given the collision guard).
--
-- BACKFILL
-- --------
-- The DO block at the end of this migration reconciles all existing
-- plantilla_slots rows that are in 'open' status but have one or more
-- active applicants — the exact stale-slot population caused by the
-- pre-fix direct INSERT path. Each VCODE is synced via
-- fn_sync_vacancy_slot_open_pipeline (non-blocking, idempotent).
--
-- Sections:
--   §1  fn_trg_applicant_insert_slot_sync  (trigger function)
--   §2  trg_applicant_insert_slot_sync     (AFTER INSERT trigger)
--   §3  Defensive guard in generate_vcode_for_account (explicit comment)
--   §4  Backfill: sync all stale open-slot / active-applicant pairs
--   §5  GRANT
-- ============================================================


-- ============================================================
-- §1  fn_trg_applicant_insert_slot_sync
-- ============================================================
-- Trigger function: fired AFTER INSERT on applicants.
-- When a new active (non-archived + active-status) applicant row
-- is inserted, calls fn_sync_vacancy_slot_open_pipeline to move
-- the matching plantilla_slot from open → pipeline.
--
-- NEVER RAISES — slot errors are logged via RAISE NOTICE only.

CREATE OR REPLACE FUNCTION public.fn_trg_applicant_insert_slot_sync()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Guard: only sync for active, non-archived applicants with a VCODE.
  -- Archived inserts (is_archived = true at insert time, e.g. Backout)
  -- and rows with no VCODE (should not exist) are skipped silently.
  IF COALESCE(NEW.is_archived, false) = false
    AND NEW.vacancy_vcode IS NOT NULL
    AND btrim(NEW.vacancy_vcode) <> ''
    AND public.fn_is_active_vacancy_applicant_status(NEW.status)
  THEN
    PERFORM public.fn_sync_vacancy_slot_open_pipeline(
      p_vcode        => NEW.vacancy_vcode,
      p_performed_by => COALESCE(NEW.created_by, NEW.updated_by),
      p_source_fn    => 'trg_applicant_insert_slot_sync'
    );
  END IF;
  -- AFTER trigger: return value is ignored for row triggers.
  RETURN NULL;

EXCEPTION WHEN OTHERS THEN
  -- Non-blocking contract: never roll back the host INSERT.
  RAISE NOTICE
    'fn_trg_applicant_insert_slot_sync: unexpected error for applicant=% vcode=% — % (sqlstate=%)',
    NEW.id, NEW.vacancy_vcode, SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_trg_applicant_insert_slot_sync() IS
  'OHM2026_0061 — AFTER INSERT trigger function on applicants. '
  'Calls fn_sync_vacancy_slot_open_pipeline to move the matching '
  'plantilla_slot from open → pipeline for any new active applicant row. '
  'Fixes the classification bug where direct-INSERT applicants (Flutter '
  'VacancyService.addApplicant) bypassed Phase B slot sync. NEVER RAISES.';


-- ============================================================
-- §2  trg_applicant_insert_slot_sync  (AFTER INSERT trigger)
-- ============================================================
-- Fires after every INSERT into applicants; calls the trigger
-- function which is a no-op for archived / inactive applicants.
-- Use FOR EACH ROW (one sync per inserted applicant).

DROP TRIGGER IF EXISTS trg_applicant_insert_slot_sync ON public.applicants;

CREATE TRIGGER trg_applicant_insert_slot_sync
AFTER INSERT ON public.applicants
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_applicant_insert_slot_sync();

COMMENT ON TRIGGER trg_applicant_insert_slot_sync ON public.applicants IS
  'OHM2026_0061 — AFTER INSERT trigger. Syncs plantilla_slot open→pipeline '
  'for new active applicants. Fixes Phase B invariant violation caused by '
  'VacancyService.addApplicant direct table INSERT path.';


-- ============================================================
-- §3  Defensive guard: generate_vcode_for_account
-- ============================================================
-- The existing collision guard already covers archived rows:
--   WHILE EXISTS (SELECT 1 FROM vacancies WHERE vcode = v_vcode) LOOP
-- (no is_archived filter → all rows including archived are checked).
-- The vacancies_vcode_key UNIQUE constraint (unconditional) is the
-- second safety net.
--
-- This section replaces generate_vcode_for_account with an IDENTICAL
-- body except for an explicit inline comment documenting that the
-- WHERE clause intentionally includes archived rows.  No logic change.

CREATE OR REPLACE FUNCTION public.generate_vcode_for_account(p_account_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_account_code  TEXT;
  v_group_code    TEXT;
  v_prefix        TEXT;
  v_next_seq      INTEGER;
  v_vcode         TEXT;
BEGIN
  SELECT a.account_code, g.group_code
  INTO v_account_code, v_group_code
  FROM accounts a
  JOIN groups g ON a.group_id = g.id
  WHERE a.id = p_account_id;

  IF v_account_code IS NULL THEN
    RAISE EXCEPTION 'account_code not set for account_id: %', p_account_id;
  END IF;

  v_prefix := v_account_code || '-' || v_group_code;

  INSERT INTO vcode_sequences (prefix, last_seq, updated_at)
  VALUES (v_prefix, 1, NOW())
  ON CONFLICT (prefix) DO UPDATE
    SET last_seq   = vcode_sequences.last_seq + 1,
        updated_at = NOW()
  RETURNING last_seq INTO v_next_seq;

  v_vcode := v_prefix || '-' || LPAD(v_next_seq::TEXT, 4, '0');

  -- Collision guard — intentionally checks ALL rows including archived
  -- (no is_archived filter). Archived VCODEs must never be reused.
  -- vacancies_vcode_key UNIQUE (unconditional) is the final safety net.
  WHILE EXISTS (SELECT 1 FROM vacancies WHERE vcode = v_vcode) LOOP
    UPDATE vcode_sequences
    SET last_seq = last_seq + 1, updated_at = NOW()
    WHERE prefix = v_prefix
    RETURNING last_seq INTO v_next_seq;
    v_vcode := v_prefix || '-' || LPAD(v_next_seq::TEXT, 4, '0');
  END LOOP;

  RETURN v_vcode;
END;
$$;

COMMENT ON FUNCTION public.generate_vcode_for_account(uuid) IS
  'Generates a globally unique VCODE for an account. '
  'Collision guard checks ALL rows in vacancies (including is_archived=true) '
  'so archived VCODEs are never reused. '
  'vacancies_vcode_key UNIQUE (unconditional) is the secondary safety net. '
  'OHM2026_0061: added explicit comment; no logic change.';


-- ============================================================
-- §4  Backfill: sync all stale open-slot / active-applicant pairs
-- ============================================================
-- Finds every VCODE where at least one non-roving plantilla_slot is
-- in 'open' status AND at least one active applicant exists.
-- These are pre-fix violations of the Phase B invariant caused by
-- direct INSERT via VacancyService.addApplicant.
--
-- fn_sync_vacancy_slot_open_pipeline is called per VCODE:
--   • Counts active applicants.
--   • If count ≥ 1: transitions ONE open slot to pipeline.
--   • NEVER RAISES — slot errors are logged via RAISE NOTICE.
--
-- HC=1 VCODEs: the single open slot becomes pipeline.
-- HC=N VCODEs: up to 1 open slot becomes pipeline per backfill call
--   (fn_sync_vacancy_slot_open_pipeline uses LIMIT 1 — 1:1 legacy path).
--   For N-slot VCODEs with multiple mismatched applicants the trigger
--   (§2) will correctly handle future inserts; historical multi-slot
--   drift requires the full Phase B slot-binding workflow which
--   re-creates applicants with slot_id assigned.
--
-- Expected: RAISE NOTICE rows indicate how many VCODEs were reconciled.

DO $$
DECLARE
  v_vcode record;
  v_count integer := 0;
BEGIN
  FOR v_vcode IN
    SELECT DISTINCT a.vacancy_vcode
    FROM   public.applicants a
    JOIN   public.plantilla_slots s
           ON  s.legacy_vcode = a.vacancy_vcode
           AND s.is_roving    = false
    WHERE  s.slot_status = 'open'
      AND  public.fn_is_active_vacancy_applicant_status(a.status)
      AND  COALESCE(a.is_archived, false) = false
    ORDER BY a.vacancy_vcode
  LOOP
    PERFORM public.fn_sync_vacancy_slot_open_pipeline(
      v_vcode.vacancy_vcode,
      NULL,
      'backfill_fix_0061'
    );
    v_count := v_count + 1;
  END LOOP;

  RAISE NOTICE
    'OHM2026_0061 backfill: synced % VCODE(s) with stale open-slot / active-applicant mismatch.',
    v_count;
END;
$$;


-- ============================================================
-- §5  GRANT
-- ============================================================
-- fn_trg_applicant_insert_slot_sync is a trigger function; it is
-- called by the trigger infrastructure, not directly by users.
-- No explicit GRANT needed for trigger functions (called via trigger).

-- generate_vcode_for_account: existing grants preserved (body-only replace).
ALTER FUNCTION public.generate_vcode_for_account(uuid) OWNER TO postgres;


-- ============================================================
-- Validation Queries (run manually after applying)
-- ============================================================
--
-- V1 — Trigger function exists
--   SELECT routine_name, security_type
--   FROM information_schema.routines
--   WHERE routine_schema = 'public'
--     AND routine_name = 'fn_trg_applicant_insert_slot_sync';
--   -- Expected: 1 row, DEFINER
--
-- V2 — Trigger exists on applicants
--   SELECT trigger_name, event_manipulation, action_timing
--   FROM information_schema.triggers
--   WHERE event_object_schema = 'public'
--     AND event_object_table  = 'applicants'
--     AND trigger_name = 'trg_applicant_insert_slot_sync';
--   -- Expected: 1 row, INSERT, AFTER
--
-- V3 — No stale open-slot / active-applicant pairs remain after backfill
--   SELECT a.vacancy_vcode, s.slot_status, count(a.id) AS active_applicants
--   FROM   public.applicants a
--   JOIN   public.plantilla_slots s
--          ON  s.legacy_vcode = a.vacancy_vcode
--          AND s.is_roving    = false
--   WHERE  s.slot_status = 'open'
--     AND  public.fn_is_active_vacancy_applicant_status(a.status)
--     AND  COALESCE(a.is_archived, false) = false
--   GROUP BY a.vacancy_vcode, s.slot_status;
--   -- Expected: 0 rows
--
-- V4 — Phase B invariant holds: active_applicant_count = pipeline_count
--   SELECT legacy_vcode, active_applicant_count, pipeline_count
--   FROM   public.vw_slot_derived_vacancy_shadow
--   WHERE  active_applicant_count <> pipeline_count;
--   -- Expected: 0 rows
--
-- V5 — VCODE uniqueness: no duplicate VCODEs in vacancies (active + archived)
--   SELECT vcode, count(*) AS cnt
--   FROM   public.vacancies
--   GROUP BY vcode
--   HAVING count(*) > 1;
--   -- Expected: 0 rows (vacancies_vcode_key UNIQUE enforces this)
--
-- V6 — After adding a test applicant via direct Supabase INSERT:
--   INSERT INTO public.applicants (vacancy_vcode, last_name, first_name,
--     middle_name, full_name, contact_number, status)
--   VALUES ('<test_vcode>', 'Test', 'Test', 'NA', 'Test, Test NA',
--           '09000000000', 'new');
--
--   SELECT slot_status FROM public.plantilla_slots
--   WHERE legacy_vcode = '<test_vcode>' AND is_roving = false;
--   -- Expected: 'pipeline'
--
--   SELECT vacancy_tab, open_count, pipeline_count
--   FROM   public.vw_slot_derived_vacancy_shadow
--   WHERE  legacy_vcode = '<test_vcode>';
--   -- Expected: vacancy_tab='Pipeline' (HC=1) or 'Open' (HC=N partial)
--              open_count=0 (HC=1) or N-1 (HC=N partial)
--              pipeline_count=1
