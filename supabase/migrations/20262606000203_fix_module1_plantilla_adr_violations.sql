-- Migration: 20262606000203_fix_module1_plantilla_adr_violations.sql
-- Created: 2026-11-26T13:17:33.766Z
-- Description: Reconcile and fix all Module 1 (Plantilla) ADR data violations:
--   1. Provision occupied slots for active non-pool personnel lacking slots (Invariant 1 & Rule 1).
--   2. Generate and assign canonical VCodes for active stores with NULL/empty VCodes (Invariant 2).
--   3. Recalculate roving fractional allocations to strict 1/N (Invariant 4).
--   4. Update fn_adr001_smoke() assertion A1 to allow On-Leave occupants (Actual HC = Active + On-Leave).
--   5. Backfill needs_hrco = false for active employees in accounts with active HRCOs (Rule 7 & Invariant 9).
--   6. Link dangling closed slots with missing store_id via legacy_vcode match.

BEGIN;

-- ------------------------------------------------------------------
-- 1. Active Stores with NULL or Empty VCode -> Generate Canonical VCode
-- ------------------------------------------------------------------
DO $$
DECLARE
  v_store record;
  v_new_vcode text;
BEGIN
  FOR v_store IN
    SELECT s.id, s.account_id, s.store_name
    FROM public.stores s
    WHERE s.is_active = true 
      AND (s.is_archived = false OR s.is_archived IS NULL)
      AND (s.vcode IS NULL OR trim(s.vcode) = '')
    ORDER BY s.created_at ASC
  LOOP
    IF v_store.account_id IS NOT NULL THEN
      v_new_vcode := public.generate_vcode_for_account(v_store.account_id);
      UPDATE public.stores
      SET vcode = v_new_vcode, updated_at = NOW()
      WHERE id = v_store.id;
      
      -- Backfill matching plantilla records under this store
      UPDATE public.plantilla
      SET vcode = v_new_vcode, updated_at = NOW()
      WHERE store_id = v_store.id AND (vcode IS NULL OR trim(vcode) = '');
    END IF;
  END LOOP;
END $$;

-- ------------------------------------------------------------------
-- 2. Resolve missing store for MORE account (KARAHO, KAREN DAVILA)
-- ------------------------------------------------------------------
DO $$
DECLARE
  v_store_id uuid;
  v_more_acc_id uuid := '4eac2236-7935-475f-91a4-89a560fc7b86'::uuid;
  v_more_grp_id uuid := '638c038a-ba76-484f-aff8-1947c9a6b0b7'::uuid;
  v_vcode text;
BEGIN
  SELECT id INTO v_store_id 
  FROM public.stores 
  WHERE account_id = v_more_acc_id AND store_name ILIKE '%MAGUINDANAO%' 
  LIMIT 1;

  IF v_store_id IS NULL THEN
    v_vcode := public.generate_vcode_for_account(v_more_acc_id);
    INSERT INTO public.stores (
      account_id, group_id, store_name, vcode, is_active, status, created_at, updated_at
    ) VALUES (
      v_more_acc_id, v_more_grp_id, 'SM MAGUINDANAO', v_vcode, true, 'active', NOW(), NOW()
    ) RETURNING id INTO v_store_id;
  END IF;

  UPDATE public.plantilla
  SET store_id = v_store_id,
      account_id = v_more_acc_id,
      chain_id = v_more_grp_id,
      vcode = COALESCE(vcode, (SELECT vcode FROM public.stores WHERE id = v_store_id)),
      updated_at = NOW()
  WHERE account = 'MORE' AND employee_no = '2026-99292';
END $$;

-- ------------------------------------------------------------------
-- 3. Provision / Reopen Occupied Slots for Active Personnel (Invariant 1 & Rule 1)
-- ------------------------------------------------------------------
DO $$
DECLARE
  v_emp record;
  v_slot_id uuid;
  v_store_vcode text;
  v_max_ordinal integer;
BEGIN
  FOR v_emp IN
    SELECT p.id, p.employee_no, p.employee_name, p.store_id, p.account_id, p.chain_id,
           p.position, p.deployment_type, p.store_name, p.vcode
    FROM public.plantilla p
    LEFT JOIN public.plantilla_slots s ON s.current_occupant_plantilla_id = p.id AND s.slot_status = 'occupied'
    WHERE p.status = 'Active'
      AND COALESCE(p.is_deleted, false) = false
      AND COALESCE(p.is_pool_employee, false) = false
      AND s.id IS NULL
    ORDER BY p.account, p.created_at
  LOOP
    IF v_emp.store_id IS NOT NULL THEN
      -- Step A: Check if a closed slot exists on this store (prior occupant match or empty occupant)
      SELECT s.id INTO v_slot_id
      FROM public.plantilla_slots s
      WHERE s.store_id = v_emp.store_id
        AND s.slot_status = 'closed'
        AND (s.current_occupant_plantilla_id = v_emp.id OR s.current_occupant_plantilla_id IS NULL)
      ORDER BY CASE WHEN s.current_occupant_plantilla_id = v_emp.id THEN 0 ELSE 1 END, s.slot_ordinal ASC
      LIMIT 1;

      IF v_slot_id IS NOT NULL THEN
        UPDATE public.plantilla_slots
        SET slot_status = 'occupied',
            current_occupant_plantilla_id = v_emp.id,
            closed_at = NULL,
            closed_by = NULL,
            closure_reason_code = NULL,
            position = COALESCE(v_emp.position, position),
            updated_at = NOW()
        WHERE id = v_slot_id;
      ELSE
        -- Step B: Check if an open slot exists on this store
        SELECT s.id INTO v_slot_id
        FROM public.plantilla_slots s
        WHERE s.store_id = v_emp.store_id
          AND s.slot_status = 'open'
        ORDER BY s.slot_ordinal ASC
        LIMIT 1;

        IF v_slot_id IS NOT NULL THEN
          UPDATE public.plantilla_slots
          SET slot_status = 'occupied',
              current_occupant_plantilla_id = v_emp.id,
              position = COALESCE(v_emp.position, position),
              updated_at = NOW()
          WHERE id = v_slot_id;
        ELSE
          -- Step C: Provision a brand-new occupied physical slot
          SELECT COALESCE(MAX(slot_ordinal), 0) INTO v_max_ordinal
          FROM public.plantilla_slots
          WHERE store_id = v_emp.store_id;

          INSERT INTO public.plantilla_slots (
            store_id, account_id, group_id, position, employment_type, is_roving,
            slot_status, current_occupant_plantilla_id, slot_ordinal, created_at, updated_at
          ) VALUES (
            v_emp.store_id,
            v_emp.account_id,
            COALESCE(v_emp.chain_id, (SELECT group_id FROM public.stores WHERE id = v_emp.store_id)),
            COALESCE(v_emp.position, 'Merchandiser'),
            CASE WHEN v_emp.deployment_type ILIKE 'roving' THEN 'roving' ELSE 'stationary' END,
            CASE WHEN v_emp.deployment_type ILIKE 'roving' THEN true ELSE false END,
            'occupied',
            v_emp.id,
            v_max_ordinal + 1,
            NOW(),
            NOW()
          );
        END IF;
      END IF;

      -- Sync plantilla VCode from store if missing
      IF v_emp.vcode IS NULL OR trim(v_emp.vcode) = '' THEN
        SELECT vcode INTO v_store_vcode FROM public.stores WHERE id = v_emp.store_id;
        IF v_store_vcode IS NOT NULL THEN
          UPDATE public.plantilla SET vcode = v_store_vcode, updated_at = NOW() WHERE id = v_emp.id;
        END IF;
      END IF;
    END IF;
  END LOOP;
END $$;

-- ------------------------------------------------------------------
-- 4. Correct Active Roving Allocations to strict 1/N (Invariant 4)
-- ------------------------------------------------------------------
WITH active_counts AS (
  SELECT plantilla_id, count(*) as store_cnt
  FROM public.employee_store_allocations
  WHERE is_active = true
  GROUP BY plantilla_id
)
UPDATE public.employee_store_allocations esa
SET filled_hc = ROUND(1.0 / ac.store_cnt, 2),
    active_store_count = ac.store_cnt
FROM active_counts ac
WHERE esa.plantilla_id = ac.plantilla_id
  AND esa.is_active = true
  AND ac.store_cnt >= 2
  AND abs(esa.filled_hc - ROUND(1.0 / ac.store_cnt, 2)) > 0.001;

-- ------------------------------------------------------------------
-- 5. Backfill needs_hrco = false for Active Plantilla with Assigned HRCO
-- ------------------------------------------------------------------
UPDATE public.plantilla p
SET needs_hrco = false,
    coordinator = COALESCE(up.full_name, up.email),
    hrco_name = COALESCE(up.full_name, up.email),
    hrco_user_id_snapshot = up.id,
    updated_at = NOW()
FROM (
  SELECT DISTINCT ON (us.account_id) us.account_id, up.id, up.full_name, up.email
  FROM public.user_scopes us
  JOIN public.users_profile up ON up.id = us.user_id
  JOIN public.roles r ON r.id = up.role_id
  WHERE r.role_name = 'HRCO'
    AND up.is_active = true
    AND up.archived_at IS NULL
  ORDER BY us.account_id, up.created_at ASC
) up
WHERE p.account_id = up.account_id
  AND p.status = 'Active'
  AND p.needs_hrco = true;

-- ------------------------------------------------------------------
-- 6. Link Dangling Closed Slots with Missing store_id via legacy_vcode
-- ------------------------------------------------------------------
UPDATE public.plantilla_slots ps
SET store_id = st.id,
    account_id = st.account_id,
    group_id = st.group_id,
    updated_at = NOW()
FROM public.stores st
WHERE ps.store_id IS NULL
  AND ps.legacy_vcode IS NOT NULL
  AND ps.legacy_vcode = st.vcode;

-- ------------------------------------------------------------------
-- 7. Update fn_adr001_smoke() A1 assertion to permit 'On Leave' occupants
-- ------------------------------------------------------------------
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
  -- A1: no occupied/filled slot with a missing or non-Active/On-Leave occupant;
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
                OR p.status NOT IN ('Active', 'On Leave')
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
                     v_slot_id, 'pipeline', NULL,
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
                     v_closed_id, 'open', NULL,
                     NULL, 'adr001 smoke synthetic (rolled back)', NULL);
          v_illegal_ok := (v_res ->> 'status') = 'blocked';
          RAISE EXCEPTION USING ERRCODE = 'OHM03',
            MESSAGE = 'adr001-smoke forced rollback (illegal probe)';
        EXCEPTION
          WHEN SQLSTATE 'OHM03' THEN
            NULL;
          WHEN OTHERS THEN
            v_illegal_ok := false;
            v_msg := 'illegal probe error: ' || SQLERRM;
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
  'ADR-001 slot-first invariant smoke test with On-Leave occupant support. '
  'Read-only from caller perspective. Run: SELECT * FROM fn_adr001_smoke();';

REVOKE ALL ON FUNCTION public.fn_adr001_smoke() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_adr001_smoke() FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_adr001_smoke() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_adr001_smoke() TO service_role;

COMMIT;
