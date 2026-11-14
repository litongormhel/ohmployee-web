-- ============================================================================
-- Migration: 20262606000023_fn_adr001_smoke.sql
-- Prompt ID: ohm#7k2d9f4a (SA-3 — Views/Smoke)
-- Date:      2026-08-03
-- Purpose:   ADR-001 database-level enforcement — repeatable smoke-test
--            function codifying the slot-first invariants delivered by this
--            prompt family (SA-1 000019/000020 slot authority + lifecycle
--            trigger, SA-2 000021 derived HC + tab priority
--            Closure -> Pipeline -> Open -> Hired, SA-3 000022
--            vw_plantilla_inactive ordering contract).
--
-- Usage:     SELECT * FROM public.fn_adr001_smoke();
--            Returns one row per assertion (case_id, pass, detail).
--
-- Guarantees:
--   * READ-ONLY from the caller's perspective: every mutation attempt runs
--     inside a subtransaction that is force-rolled-back via a sentinel
--     exception. The function leaves ZERO persistent changes.
--   * Assertions never raise; unexpected internal errors are caught per-case
--     and reported as pass=false with the SQLERRM in detail.
--
-- Assertions:
--   A1 slot/occupant coherence   A2 derived hired_count
--   A3 tab single-classification A4 inactive-view ordering
--   A5 direct-write privilege    A6-synthetic lifecycle transitions
--
-- Idempotent: CREATE OR REPLACE FUNCTION.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_adr001_smoke()
RETURNS TABLE(case_id text, pass boolean, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_ids        text;
  v_ids2       text;
  v_cnt        bigint;
  v_cnt2       bigint;
  v_slot_id    uuid;
  v_closed_id  uuid;
  v_res        jsonb;
  v_legal_ok   boolean := false;
  v_illegal_ok boolean := false;
  v_msg        text;
BEGIN
  ------------------------------------------------------------------
  -- A1: no occupied/filled slot with a missing or non-Active occupant;
  --     no hr_processing slot whose vcode has only terminal applicants.
  ------------------------------------------------------------------
  BEGIN
    -- A1a: occupied/filled slots whose current_occupant_plantilla_id is
    -- NULL, dangling, soft-deleted, or not status 'Active'.
    SELECT count(*),
           string_agg(sub.id::text, ', ')
      INTO v_cnt, v_ids
      FROM (
        SELECT s.id
          FROM public.plantilla_slots s
          LEFT JOIN public.plantilla p ON p.id = s.current_occupant_plantilla_id
         WHERE s.slot_status IN ('occupied', 'filled')
           AND (s.current_occupant_plantilla_id IS NULL
                OR p.id IS NULL
                OR p.status IS DISTINCT FROM 'Active'
                OR COALESCE(p.is_deleted, false))
         LIMIT 10
      ) sub;

    -- A1b: hr_processing slots linked (via legacy_vcode) to a vcode where
    -- at least one non-archived applicant exists and ALL of them are in a
    -- terminal status (reservation is stale, slot should have been released).
    SELECT count(*),
           string_agg(sub.id::text, ', ')
      INTO v_cnt2, v_ids2
      FROM (
        SELECT s.id
          FROM public.plantilla_slots s
         WHERE s.slot_status = 'hr_processing'
           AND EXISTS (
                 SELECT 1
                   FROM public.applicants a
                  WHERE a.vacancy_vcode = s.legacy_vcode
                    AND COALESCE(a.is_archived, false) = false)
           AND NOT EXISTS (
                 SELECT 1
                   FROM public.applicants a
                  WHERE a.vacancy_vcode = s.legacy_vcode
                    AND COALESCE(a.is_archived, false) = false
                    AND lower(a.status) NOT IN
                        ('backout', 'failed', 'rejected', 'rejected by ops',
                         'did not report', 'closed'))
         LIMIT 10
      ) sub;

    case_id := 'A1';
    pass    := (v_cnt = 0 AND v_cnt2 = 0);
    detail  := CASE
                 WHEN v_cnt = 0 AND v_cnt2 = 0 THEN
                   'no occupied/filled slot with terminal/missing occupant; '
                   'no hr_processing slot with only-terminal applicants'
                 ELSE
                   'occupied/filled with bad occupant (first 10): '
                   || COALESCE(v_ids, 'none')
                   || ' | stale hr_processing (first 10): '
                   || COALESCE(v_ids2, 'none')
               END;
    RETURN NEXT;
  EXCEPTION WHEN OTHERS THEN
    case_id := 'A1'; pass := false;
    detail  := 'internal error: ' || SQLERRM;
    RETURN NEXT;
  END;

  ------------------------------------------------------------------
  -- A2: shadow-view hired_count equals the count of Active, non-deleted
  --     plantilla rows for that vcode (codifies SA-2 20262606000021).
  ------------------------------------------------------------------
  BEGIN
    SELECT count(*),
           string_agg(sub.legacy_vcode, ', ')
      INTO v_cnt, v_ids
      FROM (
        SELECT v.legacy_vcode
          FROM public.vw_slot_derived_vacancy_shadow v
          LEFT JOIN LATERAL (
            SELECT count(*) AS active_cnt
              FROM public.plantilla p
             WHERE p.vcode = v.legacy_vcode
               AND p.status = 'Active'
               AND COALESCE(p.is_deleted, false) = false
          ) x ON true
         WHERE v.hired_count IS DISTINCT FROM x.active_cnt
         LIMIT 10
      ) sub;

    case_id := 'A2';
    pass    := (v_cnt = 0);
    detail  := CASE WHEN v_cnt = 0
                 THEN 'hired_count matches Active plantilla count for all vcodes'
                 ELSE 'mismatched vcodes (first 10): ' || COALESCE(v_ids, 'none')
               END;
    RETURN NEXT;
  EXCEPTION WHEN OTHERS THEN
    case_id := 'A2'; pass := false;
    detail  := 'internal error: ' || SQLERRM;
    RETURN NEXT;
  END;

  ------------------------------------------------------------------
  -- A3: no dual classification — vacancy_tab is single-valued per vcode,
  --     and no vcode sits in 'Open' while pipeline_count > 0
  --     (priority: Closure -> Pipeline -> Open -> Hired).
  ------------------------------------------------------------------
  BEGIN
    SELECT count(*),
           string_agg(sub.legacy_vcode, ', ')
      INTO v_cnt, v_ids
      FROM (
        SELECT v.legacy_vcode
          FROM public.vw_slot_derived_vacancy_shadow v
         GROUP BY v.legacy_vcode
        HAVING count(DISTINCT v.vacancy_tab) > 1
         LIMIT 10
      ) sub;

    SELECT count(*),
           string_agg(sub.legacy_vcode, ', ')
      INTO v_cnt2, v_ids2
      FROM (
        SELECT v.legacy_vcode
          FROM public.vw_slot_derived_vacancy_shadow v
         WHERE v.vacancy_tab = 'Open'
           AND v.pipeline_count > 0
         LIMIT 10
      ) sub;

    case_id := 'A3';
    pass    := (v_cnt = 0 AND v_cnt2 = 0);
    detail  := CASE
                 WHEN v_cnt = 0 AND v_cnt2 = 0 THEN
                   'vacancy_tab single-valued per vcode; no Open row with pipeline_count > 0'
                 ELSE
                   'multi-tab vcodes (first 10): ' || COALESCE(v_ids, 'none')
                   || ' | Open-with-pipeline vcodes (first 10): '
                   || COALESCE(v_ids2, 'none')
               END;
    RETURN NEXT;
  EXCEPTION WHEN OTHERS THEN
    case_id := 'A3'; pass := false;
    detail  := 'internal error: ' || SQLERRM;
    RETURN NEXT;
  END;

  ------------------------------------------------------------------
  -- A4: vw_plantilla_inactive exists and its row sequence honors the
  --     ordering contract: date_of_separation non-increasing, NULLs last.
  ------------------------------------------------------------------
  BEGIN
    IF to_regclass('public.vw_plantilla_inactive') IS NULL THEN
      case_id := 'A4'; pass := false;
      detail  := 'view public.vw_plantilla_inactive does not exist';
      RETURN NEXT;
    ELSE
      -- Materialize the view rows in view order and check adjacent pairs.
      EXECUTE $q$
        WITH seq AS (
          SELECT v.date_of_separation AS d,
                 row_number() OVER () AS rn
            FROM public.vw_plantilla_inactive v
        )
        SELECT count(*)
          FROM seq a
          JOIN seq b ON b.rn = a.rn + 1
         WHERE (a.d IS NULL AND b.d IS NOT NULL)                     -- NULL before non-NULL
            OR (a.d IS NOT NULL AND b.d IS NOT NULL AND a.d < b.d)   -- increasing pair
      $q$ INTO v_cnt;

      case_id := 'A4';
      pass    := (v_cnt = 0);
      detail  := CASE WHEN v_cnt = 0
                   THEN 'view exists; date_of_separation is non-increasing with NULLs last'
                   ELSE v_cnt::text || ' adjacent ordering violation(s) found'
                 END;
      RETURN NEXT;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    case_id := 'A4'; pass := false;
    detail  := 'internal error: ' || SQLERRM;
    RETURN NEXT;
  END;

  ------------------------------------------------------------------
  -- A5: synthetic, rolled-back privilege probe — role `authenticated`
  --     must NOT be able to UPDATE plantilla_slots directly.
  --     Expected: insufficient_privilege (42501) => PASS.
  --     If the write is permitted, it is force-rolled-back via a sentinel
  --     exception so no data ever changes.
  ------------------------------------------------------------------
  BEGIN
    -- Capture a target row id as definer BEFORE switching role, so the
    -- probe cannot degrade into a no-op via RLS-hidden rows.
    SELECT s.id INTO v_slot_id FROM public.plantilla_slots s LIMIT 1;

    IF v_slot_id IS NULL THEN
      case_id := 'A5'; pass := true;
      detail  := 'skipped: plantilla_slots is empty';
      RETURN NEXT;
    ELSE
      SET LOCAL ROLE authenticated;
      BEGIN
        UPDATE public.plantilla_slots
           SET slot_status = slot_status
         WHERE id = v_slot_id;
        -- Write was permitted: raise a sentinel to roll this
        -- subtransaction (and the write) back.
        RAISE EXCEPTION USING ERRCODE = 'OHM01',
          MESSAGE = 'adr001-smoke forced rollback (write permitted)';
      EXCEPTION
        WHEN insufficient_privilege THEN
          RESET ROLE;
          case_id := 'A5'; pass := true;
          detail  := 'authenticated blocked from direct UPDATE on plantilla_slots (insufficient_privilege)';
          RETURN NEXT;
        WHEN SQLSTATE 'OHM01' THEN
          RESET ROLE;
          case_id := 'A5'; pass := false;
          detail  := 'authenticated role was PERMITTED to UPDATE plantilla_slots '
                     '(attempt was rolled back; no data changed)';
          RETURN NEXT;
      END;
      RESET ROLE;  -- defensive: ensure definer context is restored
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    case_id := 'A5'; pass := false;
    detail  := 'internal error: ' || SQLERRM;
    RETURN NEXT;
  END;

  ------------------------------------------------------------------
  -- A6-synthetic: rolled-back lifecycle exercise of fn_set_slot_status.
  --   Legal:   open -> pipeline must return status 'ok' (then rolled back).
  --   Illegal: closed -> open must return status 'blocked' (no mutation).
  ------------------------------------------------------------------
  BEGIN
    SELECT s.id INTO v_slot_id
      FROM public.plantilla_slots s
     WHERE s.slot_status = 'open'
     LIMIT 1;

    SELECT s.id INTO v_closed_id
      FROM public.plantilla_slots s
     WHERE s.slot_status = 'closed'
     LIMIT 1;

    IF v_slot_id IS NULL AND v_closed_id IS NULL THEN
      case_id := 'A6-synthetic'; pass := true;
      detail  := 'skipped: no candidate slot';
      RETURN NEXT;
    ELSE
      -- Legal transition probe (force-rolled-back subtransaction).
      IF v_slot_id IS NULL THEN
        v_legal_ok := true;   -- no open slot available: treat as skipped
        v_msg := 'legal open->pipeline: skipped (no open slot)';
      ELSE
        BEGIN
          v_res := public.fn_set_slot_status(
                     v_slot_id, 'pipeline', 'ADR001_SMOKE',
                     NULL, 'adr001 smoke synthetic (rolled back)', NULL);
          v_legal_ok := (v_res ->> 'status') = 'ok';
          -- Sentinel raise: rolls back the slot UPDATE + slot_history INSERT.
          RAISE EXCEPTION USING ERRCODE = 'OHM02',
            MESSAGE = 'adr001-smoke forced rollback (legal probe)';
        EXCEPTION
          WHEN SQLSTATE 'OHM02' THEN
            NULL;  -- expected: mutation rolled back, v_legal_ok survives
          WHEN OTHERS THEN
            v_legal_ok := false;
            v_msg := 'legal probe error: ' || SQLERRM;
        END;
        IF v_msg IS NULL THEN
          v_msg := 'legal open->pipeline returned '
                   || CASE WHEN v_legal_ok THEN '''ok''' ELSE 'unexpected status' END;
        END IF;
      END IF;

      -- Illegal transition probe (fn returns 'blocked' before mutating;
      -- still wrapped for zero-persistence safety).
      IF v_closed_id IS NULL THEN
        v_illegal_ok := true;  -- no closed slot available: treat as skipped
        v_msg := v_msg || ' | illegal closed->open: skipped (no closed slot)';
      ELSE
        BEGIN
          v_res := public.fn_set_slot_status(
                     v_closed_id, 'open', 'ADR001_SMOKE',
                     NULL, 'adr001 smoke synthetic (rolled back)', NULL);
          v_illegal_ok := (v_res ->> 'status') = 'blocked';
          RAISE EXCEPTION USING ERRCODE = 'OHM03',
            MESSAGE = 'adr001-smoke forced rollback (illegal probe)';
        EXCEPTION
          WHEN SQLSTATE 'OHM03' THEN
            NULL;
          WHEN OTHERS THEN
            v_illegal_ok := false;
            v_msg := v_msg || ' | illegal probe error: ' || SQLERRM;
        END;
        v_msg := v_msg || ' | illegal closed->open returned '
                 || CASE WHEN v_illegal_ok THEN '''blocked''' ELSE 'unexpected status' END;
      END IF;

      case_id := 'A6-synthetic';
      pass    := (v_legal_ok AND v_illegal_ok);
      detail  := v_msg || ' (all mutations rolled back)';
      RETURN NEXT;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    case_id := 'A6-synthetic'; pass := false;
    detail  := 'internal error: ' || SQLERRM;
    RETURN NEXT;
  END;

  RETURN;
END;
$fn$;

COMMENT ON FUNCTION public.fn_adr001_smoke() IS
  'ohm#7k2d9f4a (2026-08-03): ADR-001 slot-first invariant smoke test. '
  'Read-only from the caller''s perspective — every mutation probe runs in a '
  'force-rolled-back subtransaction. Run: SELECT * FROM fn_adr001_smoke();';

REVOKE ALL ON FUNCTION public.fn_adr001_smoke() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_adr001_smoke() FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_adr001_smoke() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_adr001_smoke() TO service_role;
