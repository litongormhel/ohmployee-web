-- ============================================================================
-- OHM2026_0070 — Fix: Open Vacancies Without Slots Missing From Vacancy Module
-- Migration: 20260912000000_backfill_gap_vacancy_slots_and_trigger.sql
-- ============================================================================
--
-- PROBLEM:
--   Open/pipeline vacancies created after the historical backfill
--   (20260810000000_backfill_historical_vacancy_slots.sql) have no
--   corresponding plantilla_slots rows.
--
--   vw_slot_derived_vacancy_shadow INNER JOINs plantilla_slots to vacancies.
--   With no slot, the vacancy is invisible to:
--     (a) Vacancy module Open tab   (reads vw_slot_derived_vacancy_shadow)
--     (b) slot_vacant_hc in v_account_allocation_kpi  (same JOIN)
--     (c) CENCOM Required/Vacant columns              (derived from slot_vacant_hc)
--
--   Plantilla account detail Vacancy tab reads vacancies directly, so it
--   correctly shows N open records — this is the observed mismatch:
--     Plantilla detail:  Vacancy = 5   (from vacancies table)
--     Vacancy Open tab:  0             (from shadow view — no slots)
--     CENCOM Vacant:     0             (from slot_vacant_hc — no slots)
--
-- CONFIRMED AFFECTED ACCOUNT (smoke test 2026-06-05):
--   MARIZ (account_id 81160797-d25a-4204-a981-e90ff9a58932)
--   VCODEs: VMRIZG1_0019–0023 (source=manual, required_headcount=1 each)
--   All 5 vacancies: slot_count = 0
--
-- FIX — TWO PARTS:
--   §1  Backfill: create plantilla_slots (+ slot_history) for all current
--       open/pipeline non-roving non-pool vacancies that have no slot yet.
--       One slot per required_headcount (slot_ordinal 1..N).
--       Aging preserved: slot_history.created_at = COALESCE(v.vacant_date, v.created_at).
--
--   §2  Forward trigger: fn_trg_auto_create_vacancy_slot() fires AFTER INSERT
--       or AFTER UPDATE (status → Open/Pipeline) on vacancies.
--       Guards: non-pool, non-deleted, vcode IS NOT NULL, affects_required_hc.
--       Idempotent: only creates missing ordinals (MAX+1 .. N).
--
-- INVARIANTS PRESERVED:
--   • "No Plantilla Slot = No Vacancy" — vacancies still need a slot to appear.
--     This migration creates slots for existing valid open vacancies; it does
--     not relax the shadow-view JOIN predicate.
--   • Archived/deleted vacancies are excluded from both backfill and trigger.
--   • Roving vacancies are excluded (roving slot model is a separate concern).
--   • Pool vacancies excluded (is_pool_vacancy = true).
--
-- SAFETY:
--   • Full transaction — any failure rolls back both backfill DML and trigger DDL.
--   • Idempotent: NOT EXISTS guard on (legacy_vcode, slot_ordinal) composite unique
--     (uq_plantilla_slots_legacy_vcode_ordinal) prevents duplicate slots.
--   • Remarks tagged 'OHM2026_0070 gap-backfill' for traceability and reversibility.
--
-- VALIDATION (run after applying):
--   V1 – All MARIZ vacancies now have slots
--     SELECT v.vcode,
--            (SELECT COUNT(*) FROM public.plantilla_slots ps
--              WHERE ps.legacy_vcode = v.vcode) AS slot_count
--     FROM public.vacancies v
--     WHERE v.account_id = '81160797-d25a-4204-a981-e90ff9a58932'
--       AND v.status = 'Open' AND v.deleted_at IS NULL;
--     -- Expect: slot_count = 1 for each MARIZ VCODE
--
--   V2 – Shadow view returns Open rows for MARIZ
--     SELECT COUNT(*) FROM public.vw_slot_derived_vacancy_shadow
--     WHERE account_id = '81160797-d25a-4204-a981-e90ff9a58932'
--       AND vacancy_tab = 'Open';
--     -- Expect: 5
--
--   V3 – slot_vacant_hc reflects MARIZ vacancies (bypass SECURITY INVOKER)
--     SELECT COALESCE((
--       SELECT COUNT(*) FROM public.plantilla_slots ps
--       INNER JOIN public.vacancies v ON v.vcode = ps.legacy_vcode
--         AND v.deleted_at IS NULL AND COALESCE(v.is_archived,false)=false
--         AND COALESCE(v.is_pool_vacancy,false)=false
--       WHERE ps.account_id = '81160797-d25a-4204-a981-e90ff9a58932'
--         AND ps.slot_status IN ('open','pipeline')
--         AND ps.is_roving = false AND ps.legacy_vcode IS NOT NULL
--     ), 0) AS mariz_slot_vacant_hc;
--     -- Expect: 5
--
--   V4 – Trigger exists
--     SELECT tgname FROM pg_trigger
--     WHERE tgname = 'trg_auto_create_vacancy_slot';
--     -- Expect: 1 row
--
-- ============================================================================

BEGIN;

-- ============================================================================
-- §1  Backfill: create plantilla_slots for gap vacancies
-- ============================================================================

DO $$
DECLARE
  v_rec         record;
  v_slot_id     uuid;
  v_ordinal     int;
  v_max_ordinal int;
  v_aging_ts    timestamptz;
  v_store_id    uuid;
  v_inserted    int := 0;
  v_skipped     int := 0;
BEGIN
  FOR v_rec IN
    -- All open/pipeline non-roving non-pool vacancies with zero slots.
    SELECT
      v.vcode,
      v.account_id,
      v.group_id,
      v.position,
      COALESCE(v.employment_type, 'stationary')                   AS employment_type,
      GREATEST(COALESCE(v.required_headcount, 1), 1)              AS required_hc,
      CASE
        WHEN lower(v.status) = 'open'     THEN 'open'
        WHEN lower(v.status) = 'pipeline' THEN 'pipeline'
        ELSE 'open'
      END                                                          AS slot_status,
      COALESCE(v.vacant_date::timestamptz, v.created_at)          AS aging_ts
    FROM public.vacancies v
    WHERE v.deleted_at IS NULL
      AND COALESCE(v.is_archived, false)        = false
      AND COALESCE(v.is_pool_vacancy, false)    = false
      AND COALESCE(v.affects_required_hc, true) = true
      AND lower(v.status) IN ('open', 'pipeline')
      AND v.vcode IS NOT NULL
      -- Exclude any VCODE that already has at least one slot
      AND NOT EXISTS (
        SELECT 1 FROM public.plantilla_slots ps
        WHERE ps.legacy_vcode = v.vcode
      )
  LOOP
    -- Resolve store_id from stores table (legacy vacancies often have NULL store_id)
    SELECT s.id INTO v_store_id
    FROM public.stores s
    WHERE upper(s.vcode) = upper(v_rec.vcode)
      AND s.status = 'active'
    ORDER BY s.created_at
    LIMIT 1;

    -- Determine starting ordinal (MAX+1 or 1 if no existing slots)
    SELECT COALESCE(MAX(ps.slot_ordinal), 0) INTO v_max_ordinal
    FROM public.plantilla_slots ps
    WHERE ps.legacy_vcode = v_rec.vcode;

    v_aging_ts := v_rec.aging_ts;

    -- Create required_hc slots (ordinals: v_max_ordinal+1 .. v_max_ordinal+required_hc)
    FOR v_ordinal IN 1 .. v_rec.required_hc LOOP
      -- Double-guard: skip if this (legacy_vcode, slot_ordinal) already exists
      IF EXISTS (
        SELECT 1 FROM public.plantilla_slots ps2
        WHERE ps2.legacy_vcode = v_rec.vcode
          AND ps2.slot_ordinal = (v_max_ordinal + v_ordinal)
      ) THEN
        v_skipped := v_skipped + 1;
        CONTINUE;
      END IF;

      INSERT INTO public.plantilla_slots (
        store_id,
        account_id,
        group_id,
        position,
        employment_type,
        is_roving,
        slot_status,
        slot_ordinal,
        legacy_vcode,
        source_hc_request_id,
        created_at,
        updated_at
      ) VALUES (
        v_store_id,
        v_rec.account_id,
        v_rec.group_id,
        v_rec.position,
        v_rec.employment_type,
        false,
        v_rec.slot_status,
        (v_max_ordinal + v_ordinal)::smallint,
        v_rec.vcode,
        NULL,
        now(),
        now()
      )
      RETURNING id INTO v_slot_id;

      -- slot_history: tag with aging-preserving timestamp and backfill remark
      INSERT INTO public.slot_history (
        slot_id,
        account_id,
        action_type,
        old_value,
        new_value,
        reason_code,
        performed_by,
        remarks,
        created_at
      ) VALUES (
        v_slot_id,
        v_rec.account_id,
        'status_change',
        NULL,
        v_rec.slot_status,
        NULL,
        NULL,
        'OHM2026_0070 gap-backfill — slot created for open vacancy without slot',
        v_aging_ts  -- preserves SLA aging from vacant_date
      );

      v_inserted := v_inserted + 1;
    END LOOP;

  END LOOP;

  RAISE NOTICE 'OHM2026_0070 backfill: % slot(s) inserted, % ordinal(s) skipped (already existed).',
    v_inserted, v_skipped;
END$$;


-- ============================================================================
-- §2  Forward trigger: auto-create slot when a vacancy becomes Open/Pipeline
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_trg_auto_create_vacancy_slot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_required_hc  int;
  v_max_ordinal  int;
  v_slot_id      uuid;
  v_store_id     uuid;
  v_ordinal      int;
  v_slot_status  text;
  v_aging_ts     timestamptz;
  v_emp_type     text;
BEGIN
  -- Only fire for non-pool, non-deleted, non-roving, VCODE-bearing vacancies
  -- that have affects_required_hc = true (or NULL, which defaults to true).
  IF COALESCE(NEW.is_pool_vacancy, false)       = true  THEN RETURN NEW; END IF;
  IF NEW.deleted_at IS NOT NULL                          THEN RETURN NEW; END IF;
  IF NEW.vcode IS NULL                                   THEN RETURN NEW; END IF;
  IF COALESCE(NEW.affects_required_hc, true)    = false THEN RETURN NEW; END IF;

  -- Only fire when the vacancy is entering or staying at Open/Pipeline
  IF lower(NEW.status) NOT IN ('open', 'pipeline') THEN RETURN NEW; END IF;

  -- On UPDATE: skip if status did not change to/from an open state
  -- (avoids re-firing on unrelated column updates when status is already Open)
  IF TG_OP = 'UPDATE' THEN
    IF lower(OLD.status) = lower(NEW.status) THEN
      -- Status unchanged — only re-evaluate if required_headcount increased
      IF COALESCE(NEW.required_headcount, 1) <= COALESCE(OLD.required_headcount, 1) THEN
        RETURN NEW;
      END IF;
    END IF;
  END IF;

  v_required_hc := GREATEST(COALESCE(NEW.required_headcount, 1), 1);
  v_slot_status  := CASE
                      WHEN lower(NEW.status) = 'pipeline' THEN 'pipeline'
                      ELSE 'open'
                    END;
  v_aging_ts     := COALESCE(NEW.vacant_date::timestamptz, now());
  v_emp_type     := COALESCE(NEW.employment_type, 'stationary');

  -- Resolve store_id from stores table
  SELECT s.id INTO v_store_id
  FROM public.stores s
  WHERE upper(s.vcode) = upper(NEW.vcode)
    AND s.status = 'active'
  ORDER BY s.created_at
  LIMIT 1;

  -- Determine how many slots already exist for this VCODE
  SELECT COALESCE(MAX(ps.slot_ordinal), 0) INTO v_max_ordinal
  FROM public.plantilla_slots ps
  WHERE ps.legacy_vcode = NEW.vcode;

  -- Create only the missing ordinals (v_max_ordinal+1 .. required_hc)
  FOR v_ordinal IN (v_max_ordinal + 1) .. v_required_hc LOOP
    -- Idempotency guard
    IF EXISTS (
      SELECT 1 FROM public.plantilla_slots ps2
      WHERE ps2.legacy_vcode = NEW.vcode
        AND ps2.slot_ordinal = v_ordinal
    ) THEN
      CONTINUE;
    END IF;

    INSERT INTO public.plantilla_slots (
      store_id,
      account_id,
      group_id,
      position,
      employment_type,
      is_roving,
      slot_status,
      slot_ordinal,
      legacy_vcode,
      source_hc_request_id,
      created_at,
      updated_at
    ) VALUES (
      v_store_id,
      NEW.account_id,
      NEW.group_id,
      COALESCE(NEW.position, ''),
      v_emp_type,
      false,
      v_slot_status,
      v_ordinal::smallint,
      NEW.vcode,
      NULL,
      now(),
      now()
    )
    RETURNING id INTO v_slot_id;

    INSERT INTO public.slot_history (
      slot_id,
      account_id,
      action_type,
      old_value,
      new_value,
      reason_code,
      performed_by,
      remarks,
      created_at
    ) VALUES (
      v_slot_id,
      NEW.account_id,
      'status_change',
      NULL,
      v_slot_status,
      NULL,
      auth.uid(),
      'Auto-created by fn_trg_auto_create_vacancy_slot on vacancy ' || NEW.vcode,
      v_aging_ts
    );
  END LOOP;

  RETURN NEW;
END$func$;

COMMENT ON FUNCTION public.fn_trg_auto_create_vacancy_slot() IS
  'OHM2026_0070 — Auto-creates plantilla_slots for newly opened/pipeline vacancies. '
  'Fires AFTER INSERT/UPDATE on vacancies when status = Open or Pipeline. '
  'Guards: non-pool, non-deleted, VCODE not null, affects_required_hc. '
  'Idempotent: only creates missing (legacy_vcode, slot_ordinal) pairs.';

DROP TRIGGER IF EXISTS trg_auto_create_vacancy_slot ON public.vacancies;

CREATE TRIGGER trg_auto_create_vacancy_slot
  AFTER INSERT OR UPDATE OF status, required_headcount
  ON public.vacancies
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_auto_create_vacancy_slot();

COMMENT ON TRIGGER trg_auto_create_vacancy_slot ON public.vacancies IS
  'OHM2026_0070 — Fires on INSERT or status/required_headcount UPDATE. '
  'Calls fn_trg_auto_create_vacancy_slot to ensure every Open/Pipeline vacancy '
  'has corresponding plantilla_slots rows (slot-derived vacancy read model).';


-- ============================================================================
-- §3  Grants
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.fn_trg_auto_create_vacancy_slot() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_trg_auto_create_vacancy_slot() TO service_role;


COMMIT;
