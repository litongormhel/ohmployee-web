-- ============================================================================
-- Migration: 20262606000024_fix_fn_adr001_smoke_role_probe.sql
-- Prompt ID: ohm#7k2d9f4a
-- Date:      2026-08-03
-- Purpose:   Fix fn_adr001_smoke() A5 probe. The 20262606000023 version used
--            SET LOCAL ROLE / RESET ROLE inside the function body, but
--            Postgres forbids setting the "role" parameter within a
--            SECURITY DEFINER function (42501: cannot set parameter "role"
--            within security-definer function) — the whole smoke run errored.
--
--            A5 is reimplemented with catalog privilege checks:
--            has_table_privilege / has_column_privilege for BOTH anon and
--            authenticated on public.plantilla_slots (table-level UPDATE and
--            column-level UPDATE on slot_status). This is deterministic,
--            mutation-free, and proves a direct UPDATE would be denied at the
--            grant gate (the lockdown installed by 20262606000019 is
--            grant-based). All other assertions (A1–A4, A6-synthetic) are
--            unchanged from 20262606000023.
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
  v_priv       text;
BEGIN
  ------------------------------------------------------------------
  -- A1: no occupied/filled slot with a missing or non-Active occupant;
  --     no hr_processing slot whose vcode has only terminal applicants.
  ------------------------------------------------------------------
  BEGIN
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
  --     plantilla rows for that vcode (codifies 20262606000021).
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
      EXECUTE $q$
        WITH seq AS (
          SELECT v.date_of_separation AS d,
                 row_number() OVER () AS rn
            FROM public.vw_plantilla_inactive v
        )
        SELECT count(*)
          FROM seq a
          JOIN seq b ON b.rn = a.rn + 1
         WHERE (a.d IS NULL AND b.d IS NOT NULL)
            OR (a.d IS NOT NULL AND b.d IS NOT NULL AND a.d < b.d)
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
  -- A5: privilege assertion — app roles (anon, authenticated) must hold
  --     NO UPDATE privilege on public.plantilla_slots, neither table-level
  --     nor column-level on slot_status. Catalog-based (mutation-free):
  --     SET ROLE probing is not possible inside a SECURITY DEFINER function.
  ------------------------------------------------------------------
  BEGIN
    SELECT string_agg(bad.what, ', ')
      INTO v_priv
      FROM (
        SELECT r.rolname || ':table-UPDATE' AS what
          FROM pg_roles r
         WHERE r.rolname IN ('anon', 'authenticated')
           AND has_table_privilege(r.rolname, 'public.plantilla_slots', 'UPDATE')
        UNION ALL
        SELECT r.rolname || ':column-UPDATE(slot_status)'
          FROM pg_roles r
         WHERE r.rolname IN ('anon', 'authenticated')
           AND has_column_privilege(r.rolname, 'public.plantilla_slots',
                                    'slot_status', 'UPDATE')
      ) bad;

    case_id := 'A5';
    pass    := (v_priv IS NULL);
    detail  := CASE WHEN v_priv IS NULL
                 THEN 'anon/authenticated hold no table- or column-level UPDATE privilege on plantilla_slots'
                 ELSE 'privilege leak detected: ' || v_priv
               END;
    RETURN NEXT;
  EXCEPTION WHEN OTHERS THEN
    case_id := 'A5'; pass := false;
    detail  := 'internal error: ' || SQLERRM;
    RETURN NEXT;
  END;

  ------------------------------------------------------------------
  -- A6-synthetic: rolled-back lifecycle exercise of fn_set_slot_status.
  --   Legal:   open -> pipeline must return status 'ok' (then rolled back).
  --   Illegal: closed -> open without a sanctioned reason code must return
  --            status 'blocked' (no mutation).
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
      IF v_slot_id IS NULL THEN
        v_legal_ok := true;
        v_msg := 'legal open->pipeline: skipped (no open slot)';
      ELSE
        BEGIN
          v_res := public.fn_set_slot_status(
                     v_slot_id, 'pipeline', 'ADR001_SMOKE',
                     NULL, 'adr001 smoke synthetic (rolled back)', NULL);
          v_legal_ok := (v_res ->> 'status') = 'ok';
          RAISE EXCEPTION USING ERRCODE = 'OHM02',
            MESSAGE = 'adr001-smoke forced rollback (legal probe)';
        EXCEPTION
          WHEN SQLSTATE 'OHM02' THEN
            NULL;
          WHEN OTHERS THEN
            v_legal_ok := false;
            v_msg := 'legal probe error: ' || SQLERRM;
        END;
        IF v_msg IS NULL THEN
          v_msg := 'legal open->pipeline returned '
                   || CASE WHEN v_legal_ok THEN '''ok''' ELSE 'unexpected status' END;
        END IF;
      END IF;

      IF v_closed_id IS NULL THEN
        v_illegal_ok := true;
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
  'force-rolled-back subtransaction; A5 is a catalog privilege assertion. '
  'Run: SELECT * FROM fn_adr001_smoke();';

REVOKE ALL ON FUNCTION public.fn_adr001_smoke() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_adr001_smoke() FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_adr001_smoke() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_adr001_smoke() TO service_role;
