-- ============================================================================
-- OHM2026_0076B — Fix Multi-Store Fractional HC Vacancy and Inactive Allocation Cleanup
-- Migration: 20260916000000_fix_fractional_hc_vacancy_and_inactive_esa_cleanup.sql
-- ============================================================================
--
-- BUGS FIXED:
--
--   Bug 1: fn_plantilla_separation_to_vacancy hardcodes required_headcount = 1
--          in both Path A (existing store links) and Path B (ESA fallback) for
--          roving vacancy creation. Multi-store roving employees (e.g. 2023-09515
--          across VMRIZG1_0064 / VMRIZG1_0065) should have required_headcount = 0.5
--          each, not 1.
--
--   Bug 2: When a roving (or stationary) employee becomes inactive / resigned /
--          AWOL / terminated, their employee_store_allocations rows are never
--          deactivated. The live allocation sync trigger
--          (trg_sync_alloc_plantilla_upd) has a WHEN guard that excludes
--          baseline-imported employees (source_baseline_import_batch_id IS NOT
--          NULL), so those 4 inactive imported employees retained 14 active ESA
--          rows, inflating CENCOM Filled HC and Required HC counts.
--
-- ROOT CAUSE — why the sync trigger misses imported employees:
--   trg_sync_alloc_plantilla_upd fires only when
--     source_employee_import_batch_id IS NULL AND
--     source_baseline_import_batch_id IS NULL.
--   Baseline-imported employees have source_baseline_import_batch_id set, so
--   the trigger is skipped. fn_plantilla_separation_to_vacancy (fired by the
--   unconditional trg_plantilla_separation_to_vacancy trigger) is the correct
--   hook point for both live and imported employees.
--
-- FIXES:
--   §0  Drop views that depend on vacancies.required_headcount (pg blocks
--       ALTER COLUMN while views reference the column). Recreated in §5.
--       Direct:    team_performance_view, v_cencom_td_vacancies,
--                  vw_archived_vacancies, vw_vacancy_detail, vw_vacancy_list
--       Transitive: own_performance_view (→ team_performance_view)
--                   v_cencom_td_by_account, v_cencom_td_by_group,
--                   v_cencom_td_priority_queue, v_cencom_td_summary
--                   (all → v_cencom_td_vacancies)
--
--   §1  ALTER vacancies.required_headcount to numeric(10,4).
--
--   §2  Re-define fn_plantilla_separation_to_vacancy:
--       a. Use esa.filled_hc (not hardcoded 1) as required_headcount when
--          creating or updating roving vacancies.
--       b. Deactivate employee_store_allocations (is_active=false,
--          effective_end=date_of_separation) for ALL employees after separation —
--          both live and imported, both roving and stationary.
--       c. Remove AND deleted_at IS NULL from ESA UPDATE statements —
--          employee_store_allocations has no deleted_at column.
--
--   §3  Backfill — deactivate orphan active ESA rows for the 4 inactive employees
--       (14 rows identified in audit). Covers pre-existing drift not fixed by §2.
--
--   §4  Backfill — correct 7 inflated vacancy required_headcount values using the
--       canonical filled_hc from employee_store_allocations.
--
--   §5  Recreate all 9 dropped views with original logic and restore grants.
--
-- INVARIANTS PRESERVED:
--   - Vacancy Request / HC Request flow: completely unchanged.
--   - Slot-first architecture: plantilla_slots auto-created by
--     trg_auto_create_vacancy_slot after vacancy update; GREATEST(0.5, 1) → 1
--     slot per fractional VCODE (correct: 1 slot per VCODE, fractional HC).
--   - Stationary employee lifecycle: fn_sync_slot_to_open path unchanged.
--   - QA archive rollback: fn_qa_archive_operational_data_reset and its ESA
--     deactivation are separate and not touched.
--   - source_import_batch_id rows excluded from live sync (fn_sync_employee_store_
--     allocations guard preserved); we operate on plantilla_id-scoped rows only.
--   - No hard deletes.
-- ============================================================================

BEGIN;

-- ============================================================================
-- §0  Drop dependent views — deepest dependents first, then direct dependents
-- ============================================================================

-- Tier 2: views that depend on the 5 direct views
DROP VIEW IF EXISTS public.own_performance_view;
DROP VIEW IF EXISTS public.v_cencom_td_by_account;
DROP VIEW IF EXISTS public.v_cencom_td_by_group;
DROP VIEW IF EXISTS public.v_cencom_td_priority_queue;
DROP VIEW IF EXISTS public.v_cencom_td_summary;

-- Tier 1: views that directly reference vacancies.required_headcount
DROP VIEW IF EXISTS public.team_performance_view;
DROP VIEW IF EXISTS public.v_cencom_td_vacancies;
DROP VIEW IF EXISTS public.vw_archived_vacancies;
DROP VIEW IF EXISTS public.vw_vacancy_detail;
DROP VIEW IF EXISTS public.vw_vacancy_list;

-- Trigger that fires on UPDATE OF required_headcount (blocks ALTER COLUMN)
DROP TRIGGER IF EXISTS trg_auto_create_vacancy_slot ON public.vacancies;

-- ============================================================================
-- §1  Alter vacancies.required_headcount to numeric(10,4)
-- ============================================================================

ALTER TABLE public.vacancies
ALTER COLUMN required_headcount TYPE numeric(10,4)
USING required_headcount::numeric;

-- ============================================================================
-- §2  Re-define fn_plantilla_separation_to_vacancy
--     Changes from prior attempt:
--       a. Declare v_filled_hc numeric for ESA lookup
--       b. Path A: look up filled_hc per VCODE from ESA; pass to vacancy INSERT/UPDATE
--       c. Path B: select filled_hc from ESA loop cursor; pass to vacancy INSERT/UPDATE
--       d. Both paths: deactivate ESA rows after vacancy handling
--          (AND deleted_at IS NULL removed — ESA has no deleted_at column)
--       e. Stationary path: deactivate ESA rows after reopen_or_create_vacancy call
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_plantilla_separation_to_vacancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link            record;
  v_link_status     text;
  v_has_links       boolean := false;
  v_store           record;
  v_rows_updated    int;
  v_new_vacancy_id  uuid;
  v_new_link_id     uuid;
  v_filled_hc       numeric;  -- fractional HC from employee_store_allocations
BEGIN
  IF NEW.separation_status IN ('AWOL','Resigned','Endo','Others','Terminated','End of Contract')
     AND NEW.date_of_separation IS NOT NULL
     AND (
          OLD.separation_status IS DISTINCT FROM NEW.separation_status
          OR OLD.date_of_separation IS DISTINCT FROM NEW.date_of_separation
         )
  THEN

    IF COALESCE(NEW.deployment_type, '') = 'Roving' THEN

      v_link_status := CASE
        WHEN NEW.separation_status IN ('Resigned','AWOL','Terminated','End of Contract','Endo','Others')
          THEN 'Resigned'
        ELSE 'Backed Out'
      END;

      -- Check if any active plantilla_store_links exist for this plantilla row
      SELECT EXISTS (
        SELECT 1
        FROM public.plantilla_store_links psl
        WHERE psl.plantilla_id = NEW.id
          AND psl.deleted_at IS NULL
          AND psl.status = 'Active'
      ) INTO v_has_links;

      IF v_has_links THEN
        -- ── Path A: loop through existing active store links ──────────────
        FOR v_link IN
          SELECT psl.id, psl.vacancy_id, psl.vcode, psl.store_name, psl.account
            FROM public.plantilla_store_links psl
           WHERE psl.plantilla_id = NEW.id
             AND psl.deleted_at IS NULL
             AND psl.status = 'Active'
        LOOP
          UPDATE public.plantilla_store_links
             SET status      = v_link_status,
                 unlinked_at = now(),
                 updated_at  = now()
           WHERE id = v_link.id;

          -- Look up fractional HC from ESA for this VCODE.
          -- Query is not filtered by is_active because the deactivation runs later
          -- in this same call. Order by created_at DESC → most recent allocation wins.
          SELECT COALESCE(esa.filled_hc, 1)
            INTO v_filled_hc
            FROM public.employee_store_allocations esa
           WHERE esa.plantilla_id = NEW.id
             AND upper(esa.vcode) = upper(v_link.vcode)
           ORDER BY esa.created_at DESC
           LIMIT 1;

          v_filled_hc := COALESCE(v_filled_hc, 1);

          -- Reopen or create vacancy
          IF v_link.vacancy_id IS NOT NULL THEN
            UPDATE public.vacancies
               SET status              = 'Open',
                   is_archived         = false,
                   archived_at         = NULL,
                   has_pending_closure = false,
                   vacant_date         = COALESCE(NEW.date_of_separation, CURRENT_DATE),
                   required_headcount  = v_filled_hc,
                   updated_at          = now()
             WHERE id = v_link.vacancy_id;
          ELSE
            UPDATE public.vacancies
               SET status              = 'Open',
                   is_archived         = false,
                   archived_at         = NULL,
                   has_pending_closure = false,
                   vacant_date         = COALESCE(NEW.date_of_separation, CURRENT_DATE),
                   required_headcount  = v_filled_hc,
                   updated_at          = now()
             WHERE vcode      = v_link.vcode;

            GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

            IF v_rows_updated = 0 THEN
              -- Fetch store details for vacancy creation
              SELECT s.id AS store_id, s.store_name, s.account_id, a.account_name, s.group_id
                INTO v_store
                FROM public.stores s
                LEFT JOIN public.accounts a ON a.id = s.account_id
               WHERE upper(s.vcode) = upper(v_link.vcode) AND s.status = 'active'
               ORDER BY s.created_at ASC
               LIMIT 1;

              INSERT INTO public.vacancies (
                vcode, account, position, account_id, chain_id, store_id, province_id,
                area_name, position_id, vacant_date, vacancy_type, status,
                source_plantilla_id, store_name, created_at, updated_at,
                required_headcount
              )
              VALUES (
                v_link.vcode,
                COALESCE(v_store.account_name, v_link.account, NEW.account, 'UNKNOWN'),
                NEW.position,
                COALESCE(v_store.account_id, NEW.account_id),
                NEW.chain_id,
                v_store.store_id,
                NEW.province_id,
                COALESCE(NEW.area_name_snapshot, NEW.area),
                NEW.position_id,
                COALESCE(NEW.date_of_separation, CURRENT_DATE),
                'Backfill',
                'Open',
                NULL,  -- NULL to respect uq_vacancy_source_plantilla (roving 1-to-many)
                COALESCE(v_store.store_name, v_link.store_name),
                now(),
                now(),
                v_filled_hc  -- fractional HC from ESA; was hardcoded 1 before this fix
              )
              RETURNING id INTO v_new_vacancy_id;

              UPDATE public.plantilla_store_links
                 SET vacancy_id = v_new_vacancy_id
               WHERE id = v_link.id;
            END IF;
          END IF;
        END LOOP;  -- end Path A loop

      ELSE
        -- ── Path B: fallback — no store links, use active ESA allocations ─
        FOR v_link IN
          SELECT esa.vcode, esa.store_name, esa.store_id, esa.account_id,
                 COALESCE(esa.filled_hc, 1) AS filled_hc  -- fractional HC
            FROM public.employee_store_allocations esa
           WHERE esa.plantilla_id = NEW.id
             AND esa.is_active = true
        LOOP
          v_filled_hc := v_link.filled_hc;

          -- Fetch store details
          SELECT s.id AS store_id, s.store_name, s.account_id, a.account_name, s.group_id
            INTO v_store
            FROM public.stores s
            LEFT JOIN public.accounts a ON a.id = s.account_id
           WHERE upper(s.vcode) = upper(v_link.vcode) AND s.status = 'active'
           ORDER BY s.created_at ASC
           LIMIT 1;

          -- Insert historical link
          INSERT INTO public.plantilla_store_links (
            plantilla_id, roving_assignment_id, vcode, store_name, account,
            status, linked_at, unlinked_at, created_at, updated_at
          )
          VALUES (
            NEW.id,
            NULL,
            v_link.vcode,
            COALESCE(v_store.store_name, v_link.store_name),
            COALESCE(v_store.account_name, NEW.account, 'UNKNOWN'),
            v_link_status,
            now(), now(), now(), now()
          )
          RETURNING id INTO v_new_link_id;

          -- Reopen vacancy by VCODE
          UPDATE public.vacancies
             SET status              = 'Open',
                 is_archived         = false,
                 archived_at         = NULL,
                 has_pending_closure = false,
                 vacant_date         = COALESCE(NEW.date_of_separation, CURRENT_DATE),
                 required_headcount  = v_filled_hc,  -- fractional HC from ESA
                 updated_at          = now()
           WHERE vcode      = v_link.vcode;

          GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

          IF v_rows_updated = 0 THEN
            -- Vacancy missing entirely — create as Open
            INSERT INTO public.vacancies (
              vcode, account, position, account_id, chain_id, store_id, province_id,
              area_name, position_id, vacant_date, vacancy_type, status,
              source_plantilla_id, store_name, created_at, updated_at,
              required_headcount
            )
            VALUES (
              v_link.vcode,
              COALESCE(v_store.account_name, NEW.account, 'UNKNOWN'),
              NEW.position,
              COALESCE(v_store.account_id, NEW.account_id),
              NEW.chain_id,
              v_store.store_id,
              NEW.province_id,
              COALESCE(NEW.area_name_snapshot, NEW.area),
              NEW.position_id,
              COALESCE(NEW.date_of_separation, CURRENT_DATE),
              'Backfill',
              'Open',
              NULL,  -- NULL to respect uq_vacancy_source_plantilla (roving 1-to-many)
              COALESCE(v_store.store_name, v_link.store_name),
              now(),
              now(),
              v_filled_hc  -- fractional HC from ESA; was hardcoded 1 before this fix
            )
            RETURNING id INTO v_new_vacancy_id;

            UPDATE public.plantilla_store_links
               SET vacancy_id = v_new_vacancy_id
             WHERE id = v_new_link_id;
          ELSE
            -- Link existing reopened vacancy to the new historical store link
            UPDATE public.plantilla_store_links
               SET vacancy_id = (
                 SELECT id FROM public.vacancies
                  WHERE vcode = v_link.vcode
                  ORDER BY created_at ASC
                  LIMIT 1
               )
             WHERE id = v_new_link_id;
          END IF;
        END LOOP;  -- end Path B loop
      END IF;

      -- ── Deactivate ESA rows for this roving employee after vacancy handling ─
      -- Covers baseline-imported employees skipped by trg_sync_alloc_plantilla_upd.
      -- Note: employee_store_allocations has no deleted_at column.
      UPDATE public.employee_store_allocations
         SET is_active     = false,
             effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
       WHERE plantilla_id = NEW.id
         AND is_active    = true;

      RETURN NEW;
    END IF;

    -- ── Stationary employee path ─────────────────────────────────────────────
    PERFORM public.reopen_or_create_vacancy_for_plantilla(
      NEW.id,
      NEW.date_of_separation,
      'Backfill'
    );

    -- Deactivate ESA rows for stationary employees (safety: baseline imports
    -- skipped by trg_sync_alloc_plantilla_upd reach this cleanup path too).
    -- Note: employee_store_allocations has no deleted_at column.
    UPDATE public.employee_store_allocations
       SET is_active     = false,
           effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
     WHERE plantilla_id = NEW.id
       AND is_active    = true;
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.fn_plantilla_separation_to_vacancy() IS
  'OHM2026_0076B — Fires trg_plantilla_separation_to_vacancy AFTER UPDATE on plantilla. '
  'For Roving employees: updates/creates vacancies using esa.filled_hc (not hardcoded 1) '
  'for fractional multi-store required_headcount, then deactivates all ESA rows for the '
  'employee. Covers baseline-imported employees excluded from trg_sync_alloc_plantilla_upd. '
  'For Stationary employees: calls reopen_or_create_vacancy_for_plantilla then deactivates ESA. '
  'Roving Path A: uses existing plantilla_store_links. '
  'Roving Path B: falls back to active employee_store_allocations when links absent. '
  'Fix vs 0076: AND deleted_at IS NULL removed from ESA UPDATE statements '
  '(employee_store_allocations has no deleted_at column). '
  'History preserved — no hard deletes. Vacancy Request/HC Request flow unchanged.';


-- ============================================================================
-- §3  Backfill — deactivate orphan active ESA rows for inactive employees
--
--     Target: employees whose plantilla.status is terminal (not an active
--     deployment state) but who still have is_active ESA rows. The 4 identified
--     inactive employees with 14 active ESA rows are baseline imports; their
--     plantilla status changed to Inactive but the sync trigger was skipped.
--
--     Active deployment states (keep ESA active):
--       'Active', 'For Deactivation', 'On Leave', 'Pending Deactivation',
--       'Rejected Deactivation'  ← deactivation was rejected → still deployed
--
--     Terminal states (deactivate ESA):
--       'Inactive', 'Deactivated', 'Resigned', 'Transferred', and any other
--       status not in the active set above.
--
--     effective_end = date_of_separation when available, CURRENT_DATE fallback.
-- ============================================================================
UPDATE public.employee_store_allocations esa
   SET is_active    = false,
       effective_end = COALESCE(
         (
           SELECT p.date_of_separation
             FROM public.plantilla p
            WHERE p.id = esa.plantilla_id
              AND p.is_deleted = false
            ORDER BY p.created_at DESC
            LIMIT 1
         ),
         CURRENT_DATE
       )
 WHERE esa.is_active  = true
   AND EXISTS (
     SELECT 1
       FROM public.plantilla p
      WHERE p.id = esa.plantilla_id
        AND p.is_deleted = false
        AND p.status NOT IN (
          'Active',
          'For Deactivation',
          'On Leave',
          'Pending Deactivation',
          'Rejected Deactivation'
        )
   );


-- ============================================================================
-- §4  Backfill — correct inflated vacancy required_headcount
--
--     Target: Open/Pipeline vacancies where the VCODE has a fractional
--     (< 1) ESA allocation but the vacancy still has required_headcount = 1
--     (set by the previous hardcoded value in fn_plantilla_separation_to_vacancy).
--
--     Source of truth: employee_store_allocations.filled_hc — most recently
--     created non-deleted ESA row per VCODE.
--
--     Guard: only updates vacancies where the allocation is fractional
--     (filled_hc < 1) AND the vacancy's HC is currently inflated above it.
--     Stationary vacancies (filled_hc = 1) and HC Request vacancies
--     (no matching ESA) are not touched.
-- ============================================================================
WITH esa_frac AS (
  SELECT DISTINCT ON (vcode)
    vcode,
    filled_hc
  FROM public.employee_store_allocations WHERE true
    AND filled_hc IS NOT NULL
    AND filled_hc > 0
    AND filled_hc < 1          -- fractional multi-store allocations only
  ORDER BY vcode, created_at DESC
)
UPDATE public.vacancies v
   SET required_headcount = ef.filled_hc,
       updated_at         = now()
  FROM esa_frac ef
 WHERE v.vcode             = ef.vcode
   AND v.status            IN ('Open', 'Pipeline')
   AND v.is_archived       = false
   AND v.deleted_at        IS NULL
   AND v.required_headcount > ef.filled_hc;  -- only correct inflated values


-- ============================================================================
-- §5  Recreate dependent views — leaf views first, then tier-2 dependents
--     Definitions captured verbatim from pg_get_viewdef before this migration.
--     Grants restored to match pre-drop state: ALL on authenticated, postgres,
--     service_role (uniform across all 9 views).
-- ============================================================================

-- ── team_performance_view ───────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.team_performance_view AS
 WITH user_base AS (
         SELECT up.id AS profile_id,
            up.auth_user_id AS auth_uid,
            up.full_name,
            r.role_name AS role,
            up.group_id
           FROM users_profile up
             JOIN roles r ON r.id = up.role_id
          WHERE up.is_active = true AND (r.role_name = ANY (ARRAY['HRCO'::text, 'ATL'::text, 'TL'::text, 'Operations Manager'::text]))
        ), perf AS (
         SELECT ub.profile_id,
            ub.auth_uid,
            ub.full_name,
            ub.role,
            ub.group_id,
            COALESCE(( SELECT sum(v.required_headcount) AS sum
                   FROM vacancies v
                  WHERE (v.is_archived IS NULL OR v.is_archived = false) AND (ub.role = 'HRCO'::text AND v.hrco_user_id = ub.profile_id OR ub.role = 'ATL'::text AND v.atl_user_id = ub.profile_id OR ub.role = 'Operations Manager'::text AND v.om_user_id = ub.profile_id OR ub.role = 'TL'::text AND (v.account_id IN ( SELECT us.account_id
                           FROM user_scopes us
                          WHERE us.user_id = ub.profile_id AND us.account_id IS NOT NULL)))), 0::bigint)::integer AS required_count,
            COALESCE(( SELECT count(*) AS count
                   FROM plantilla p
                  WHERE p.status = 'Active'::text AND (ub.role = 'HRCO'::text AND p.hrco_user_id_snapshot = ub.profile_id OR ub.role = 'ATL'::text AND p.atl_user_id_snapshot = ub.profile_id OR ub.role = 'Operations Manager'::text AND p.om_user_id_snapshot = ub.profile_id OR ub.role = 'TL'::text AND (p.account_id IN ( SELECT us.account_id
                           FROM user_scopes us
                          WHERE us.user_id = ub.profile_id AND us.account_id IS NOT NULL)))), 0::bigint)::integer AS actual_count,
            COALESCE(( SELECT count(*) AS count
                   FROM hr_emploc he
                  WHERE he.status <> 'Moved to Plantilla'::text AND (ub.role = 'HRCO'::text AND he.hrco_user_id_snapshot = ub.profile_id OR ub.role = 'ATL'::text AND he.atl_user_id_snapshot = ub.profile_id OR ub.role = 'Operations Manager'::text AND he.om_user_id_snapshot = ub.profile_id OR ub.role = 'TL'::text AND (he.account_id IN ( SELECT us.account_id
                           FROM user_scopes us
                          WHERE us.user_id = ub.profile_id AND us.account_id IS NOT NULL)))), 0::bigint)::integer AS hr_emploc_count
           FROM user_base ub
        )
 SELECT profile_id,
    auth_uid,
    full_name,
    role,
    group_id,
    required_count,
    actual_count,
    hr_emploc_count,
    GREATEST(required_count - (actual_count + hr_emploc_count), 0) AS vacant_count,
        CASE
            WHEN required_count = 0 THEN NULL::numeric
            ELSE round(actual_count::numeric / required_count::numeric * 100::numeric, 2)
        END AS mfr,
        CASE
            WHEN required_count = 0 THEN NULL::numeric
            ELSE round(hr_emploc_count::numeric / required_count::numeric * 100::numeric, 2)
        END AS pipeline_percent,
        CASE
            WHEN required_count = 0 THEN 'No Data'::text
            WHEN round(actual_count::numeric / required_count::numeric * 100::numeric, 2) >= 95::numeric THEN 'Excellent'::text
            WHEN round(actual_count::numeric / required_count::numeric * 100::numeric, 2) >= 80::numeric THEN 'Needs Attention'::text
            ELSE 'Critical'::text
        END AS perf_status,
        CASE
            WHEN required_count = 0 THEN 'No Required Set'::text
            WHEN round(actual_count::numeric / required_count::numeric * 100::numeric, 2) < 80::numeric AND hr_emploc_count = 0 THEN 'CRITICAL: No Pipeline'::text
            WHEN round(actual_count::numeric / required_count::numeric * 100::numeric, 2) < 80::numeric AND hr_emploc_count > 0 THEN 'In Progress'::text
            WHEN GREATEST(required_count - (actual_count + hr_emploc_count), 0) > 0 THEN 'Vacant Warning'::text
            ELSE NULL::text
        END AS alert_flag
   FROM perf;

GRANT ALL ON public.team_performance_view TO authenticated, postgres, service_role;


-- ── v_cencom_td_vacancies ───────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_cencom_td_vacancies AS
 SELECT v.id AS vacancy_id,
    v.vcode,
    v.account,
    v.account_id,
    v."position",
    COALESCE(v.area_name, v.area_city) AS area_name,
    COALESCE(v.store_name, v.store_branch) AS store_name,
    v.vacant_date,
    v.vacancy_type,
    COALESCE(v.urgency_level, 'Normal'::text) AS urgency_level,
    v.target_fill_date,
    v.required_headcount,
    v.source,
    ak.group_id,
    ak.group_name,
    ak.group_code,
    ak.mfr AS account_mfr,
    ak.actual_hc AS account_actual_hc,
    ak.required_hc AS account_required_hc,
    ak.health_status AS account_health_status,
    v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE AS is_advance_vacancy,
        CASE
            WHEN v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE THEN NULL::integer
            ELSE GREATEST(0, CURRENT_DATE - v.vacant_date)
        END AS aging_days,
    fn_cencom_td_aging_bucket(
        CASE
            WHEN v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE THEN NULL::integer
            ELSE GREATEST(0, CURRENT_DATE - v.vacant_date)
        END, v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE) AS aging_bucket,
    fn_cencom_td_priority_score(
        CASE
            WHEN v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE THEN NULL::integer
            ELSE GREATEST(0, CURRENT_DATE - v.vacant_date)
        END, COALESCE(v.urgency_level, 'Normal'::text), v.required_headcount::integer, ak.mfr) AS priority_score,
        CASE
            WHEN COALESCE(ak.mfr, 1.0) < 0.75 THEN 'critical'::text
            WHEN COALESCE(ak.mfr, 1.0) < 0.85 THEN 'at_risk'::text
            WHEN COALESCE(ak.mfr, 1.0) < 0.90 THEN 'elevated'::text
            ELSE 'healthy'::text
        END AS account_health_tier,
        CASE
            WHEN v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE THEN 'advance'::text
            WHEN GREATEST(0, CURRENT_DATE - v.vacant_date) >= 61 AND COALESCE(ak.mfr, 1.0) < 0.85 THEN 'immediate'::text
            WHEN GREATEST(0, CURRENT_DATE - v.vacant_date) >= 31 OR COALESCE(ak.mfr, 1.0) < 0.80 THEN 'critical'::text
            WHEN GREATEST(0, CURRENT_DATE - v.vacant_date) >= 16 OR COALESCE(ak.mfr, 1.0) < 0.90 THEN 'elevated'::text
            ELSE 'normal'::text
        END AS urgency_tier
   FROM vacancies v
     JOIN v_cencom_account_kpi ak ON ak.account_id = v.account_id
  WHERE (v.status = ANY (ARRAY['Open'::text, 'For Sourcing'::text])) AND COALESCE(v.is_archived, false) = false AND v.deleted_at IS NULL;

GRANT ALL ON public.v_cencom_td_vacancies TO authenticated, postgres, service_role;


-- ── vw_archived_vacancies ───────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.vw_archived_vacancies AS
 SELECT v.id,
    v.vcode,
    v.account,
    v."position",
    v.status,
    v.backout_reason,
    v.created_at,
    v.vacancy_code,
    v.vacancy_type,
    v.account_id,
    v.chain_id,
    v.store_id,
    v.province_id,
    v.area_name,
    v.hrco_user_id,
    v.om_user_id,
    v.atl_user_id,
    v.position_id,
    v.vacant_date,
    v.required_headcount,
    v.has_penalty,
    v.penalty_amount,
    v.has_reliever,
    v.reliever_name,
    v.remarks,
    v.requested_by_user_id,
    v.requested_date,
    v.created_by_user_id,
    v.closure_request_status,
    v.archived_at,
    v.archived_by,
    v.created_by,
    v.updated_at,
    v.updated_by,
    v.chain,
    v.province,
    v.store_branch,
    v.hrco_name,
    v.hrco_mobile,
    v.om_name,
    v.is_archived,
    v.has_pending_closure,
    v.store_name,
    v.area_city,
    v.penalty_aging_detail,
    v.assigned_encoder_id,
    v.source_plantilla_id,
    v.deleted_at,
    v.source,
    v.source_vacancy_request_id,
    v.urgency_level,
    v.target_fill_date,
    v.triggered_by_user_id,
    v.triggered_by_name,
    v.employment_type,
    v.group_id,
    v.source_headcount_request_id,
    v.is_pool_vacancy,
    v.pool_type_id,
    v.home_account_id,
    v.affects_required_hc,
    v.affects_mfr,
    v.pool_request_id,
    v.archive_reason,
    v.restored_at,
    v.restored_by,
    v.archived_by_id,
    up_arc.full_name AS archived_by_name,
    up_rst.full_name AS restored_by_name
   FROM vacancies v
     LEFT JOIN users_profile up_arc ON up_arc.id = v.archived_by_id
     LEFT JOIN users_profile up_rst ON up_rst.id = v.restored_by
  WHERE v.is_archived = true;

GRANT ALL ON public.vw_archived_vacancies TO authenticated, postgres, service_role;


-- ── vw_vacancy_detail ───────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.vw_vacancy_detail AS
 WITH applicant_stats AS (
         SELECT a.vacancy_vcode,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND (a.status <> ALL (ARRAY['Failed'::text, 'Backout'::text, 'Did Not Report'::text, 'Rejected by Ops'::text, 'Confirmed Onboard'::text]))) AS active_applicant_count,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text) AS confirmed_onboard_count,
            max(a.hired_at) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text) AS latest_hire_at,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text AND COALESCE(a.hired_visible_until, a.hired_at + '7 days'::interval) > now()) > 0 AS has_recent_hire
           FROM applicants a
          GROUP BY a.vacancy_vcode
        )
 SELECT v.id,
    v.vcode,
    v.account,
    v.account_id,
    v.store_name,
    v.store_id,
    v.area_name,
    v.area_city,
    v."position",
    v.position_id,
    v.employment_type,
    v.status,
        CASE
            WHEN v.is_archived = true OR (v.status = ANY (ARRAY['Closed'::text, 'Archived'::text])) THEN 'Archived'::text
            WHEN v.status = 'Filled'::text THEN 'Hired'::text
            WHEN COALESCE(s.active_applicant_count, 0::bigint) > 0 THEN 'Pipeline'::text
            ELSE 'Open'::text
        END AS derived_status,
    v.source,
    v.source_vacancy_request_id,
    v.source_plantilla_id,
    v.vacancy_type,
    v.urgency_level,
    v.target_fill_date,
    v.required_headcount AS hc_needed,
    v.triggered_by_user_id,
    v.triggered_by_name,
    v.vacant_date,
    CURRENT_DATE - v.vacant_date AS aging_days,
    v.created_at,
    v.created_by,
    v.updated_at,
    v.is_archived,
    v.archived_at,
    v.closure_request_status,
    v.has_pending_closure,
    COALESCE(s.active_applicant_count, 0::bigint) AS active_applicant_count,
    COALESCE(s.confirmed_onboard_count, 0::bigint) AS confirmed_onboard_count,
    s.latest_hire_at,
    v.assigned_encoder_id,
    v.has_reliever,
    v.reliever_name,
    v.requested_by_user_id,
    v.requested_date,
    v.group_id,
    g.group_name,
    v.hrco_user_id,
    v.hrco_name,
    COALESCE(up.full_name, v.triggered_by_name) AS triggered_by_full_name,
    NULL::text AS triggered_by_role,
    vr.vacancy_type AS hc_request_type,
    vr.requested_by AS hc_request_requested_by,
    vr.requested_by_user_id AS hc_request_requested_by_user_id,
    vr.created_at AS hc_request_date_created,
    vr.no_of_slots AS hc_request_no_of_slots,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire,
    v.request_type
   FROM vacancies v
     LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
     LEFT JOIN groups g ON g.id = v.group_id
     LEFT JOIN users_profile up ON up.id = v.triggered_by_user_id
     LEFT JOIN vacancy_requests vr ON vr.id = v.source_vacancy_request_id
  WHERE v.deleted_at IS NULL;

GRANT ALL ON public.vw_vacancy_detail TO authenticated, postgres, service_role;


-- ── vw_vacancy_list ─────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.vw_vacancy_list AS
 WITH applicant_stats AS (
         SELECT a.vacancy_vcode,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND (a.status <> ALL (ARRAY['Failed'::text, 'Backout'::text, 'Did Not Report'::text, 'Rejected by Ops'::text, 'Confirmed Onboard'::text]))) AS active_applicant_count,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text) AS confirmed_onboard_count,
            max(a.hired_at) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text) AS latest_hire_at,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text AND COALESCE(a.hired_visible_until, a.hired_at + '7 days'::interval) > now()) > 0 AS has_recent_hire
           FROM applicants a
          GROUP BY a.vacancy_vcode
        )
 SELECT v.id,
    v.vcode,
    v.account,
    v.account_id,
    v.store_name,
    v.store_id,
    v.area_name,
    v.area_city,
    v.province,
    v.store_branch,
    v."position",
    v.position_id,
    v.employment_type,
    v.status,
        CASE
            WHEN v.is_archived = true OR (v.status = ANY (ARRAY['Closed'::text, 'Archived'::text])) THEN 'Archived'::text
            WHEN v.status = 'Filled'::text THEN 'Hired'::text
            WHEN COALESCE(s.active_applicant_count, 0::bigint) > 0 THEN 'Pipeline'::text
            ELSE 'Open'::text
        END AS derived_status,
    v.source,
    v.source_vacancy_request_id,
    v.source_plantilla_id,
    v.vacancy_type,
    v.urgency_level,
    v.target_fill_date,
    v.required_headcount AS hc_needed,
    v.triggered_by_user_id,
    v.triggered_by_name,
    v.vacant_date,
    CURRENT_DATE - v.vacant_date AS aging_days,
    v.created_at,
    v.created_by,
    v.updated_at,
    v.is_archived,
    v.archived_at,
    v.closure_request_status,
    v.has_pending_closure,
    COALESCE(s.active_applicant_count, 0::bigint) AS active_applicant_count,
    COALESCE(s.confirmed_onboard_count, 0::bigint) AS confirmed_onboard_count,
    s.latest_hire_at,
    v.assigned_encoder_id,
    v.group_id,
    g.group_name,
    v.hrco_user_id,
        CASE
            WHEN up_hrco.is_active = true AND r_hrco.role_name = 'HRCO'::text THEN up_hrco.full_name
            ELSE NULL::text
        END AS hrco_name,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire
   FROM vacancies v
     LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
     LEFT JOIN groups g ON g.id = v.group_id
     LEFT JOIN users_profile up_hrco ON up_hrco.id = v.hrco_user_id
     LEFT JOIN roles r_hrco ON r_hrco.id = up_hrco.role_id
  WHERE v.deleted_at IS NULL;

GRANT ALL ON public.vw_vacancy_list TO authenticated, postgres, service_role;


-- ── own_performance_view (depends on team_performance_view) ─────────────────
CREATE OR REPLACE VIEW public.own_performance_view AS
 SELECT profile_id,
    auth_uid,
    full_name,
    role,
    group_id,
    required_count,
    actual_count,
    hr_emploc_count,
    vacant_count,
    mfr,
    pipeline_percent,
    perf_status,
    alert_flag,
    rank() OVER (PARTITION BY role ORDER BY (COALESCE(mfr, 0::numeric)) DESC) AS rank_within_role,
    count(*) OVER (PARTITION BY role) AS total_in_role
   FROM team_performance_view tp
  WHERE auth_uid = auth.uid();

GRANT ALL ON public.own_performance_view TO authenticated, postgres, service_role;


-- ── v_cencom_td_by_account (depends on v_cencom_td_vacancies) ───────────────
CREATE OR REPLACE VIEW public.v_cencom_td_by_account AS
 SELECT account_id,
    account,
    group_id,
    group_name,
    group_code,
    account_mfr,
    account_health_tier,
    account_health_status,
    count(*) FILTER (WHERE NOT is_advance_vacancy) AS operational_total,
    count(*) FILTER (WHERE is_advance_vacancy) AS advance_count,
    count(*) AS grand_total,
    count(*) FILTER (WHERE aging_bucket = '1_15'::text) AS bucket_1_15,
    count(*) FILTER (WHERE aging_bucket = '16_30'::text) AS bucket_16_30,
    count(*) FILTER (WHERE aging_bucket = '31_60'::text) AS bucket_31_60,
    count(*) FILTER (WHERE aging_bucket = '61_120'::text) AS bucket_61_120,
    count(*) FILTER (WHERE aging_bucket = 'gt121'::text) AS bucket_gt121,
    max(aging_days) AS max_aging_days,
    round(avg(aging_days), 1) AS avg_aging_days,
    max(priority_score) FILTER (WHERE NOT is_advance_vacancy) AS max_priority_score,
    count(*) FILTER (WHERE urgency_tier = ANY (ARRAY['immediate'::text, 'critical'::text])) AS urgent_count
   FROM v_cencom_td_vacancies
  GROUP BY account_id, account, group_id, group_name, group_code, account_mfr, account_health_tier, account_health_status
  ORDER BY (max(priority_score) FILTER (WHERE NOT is_advance_vacancy)) DESC NULLS LAST;

GRANT ALL ON public.v_cencom_td_by_account TO authenticated, postgres, service_role;


-- ── v_cencom_td_by_group (depends on v_cencom_td_vacancies) ─────────────────
CREATE OR REPLACE VIEW public.v_cencom_td_by_group AS
 SELECT group_id,
    group_name,
    group_code,
    count(*) FILTER (WHERE NOT is_advance_vacancy) AS operational_total,
    count(*) FILTER (WHERE is_advance_vacancy) AS advance_count,
    count(*) AS grand_total,
    count(*) FILTER (WHERE aging_bucket = '1_15'::text) AS bucket_1_15,
    count(*) FILTER (WHERE aging_bucket = '16_30'::text) AS bucket_16_30,
    count(*) FILTER (WHERE aging_bucket = '31_60'::text) AS bucket_31_60,
    count(*) FILTER (WHERE aging_bucket = '61_120'::text) AS bucket_61_120,
    count(*) FILTER (WHERE aging_bucket = 'gt121'::text) AS bucket_gt121,
    count(*) FILTER (WHERE urgency_tier = 'immediate'::text) AS urgency_immediate,
    count(*) FILTER (WHERE urgency_tier = 'critical'::text) AS urgency_critical,
    count(*) FILTER (WHERE urgency_tier = 'elevated'::text) AS urgency_elevated,
    max(aging_days) AS max_aging_days,
    round(avg(aging_days), 1) AS avg_aging_days,
    max(priority_score) FILTER (WHERE NOT is_advance_vacancy) AS max_priority_score,
        CASE
            WHEN count(*) FILTER (WHERE NOT is_advance_vacancy AND account_health_tier = 'critical'::text) > 0 THEN 'critical'::text
            WHEN count(*) FILTER (WHERE NOT is_advance_vacancy AND account_health_tier = 'at_risk'::text) > 0 THEN 'at_risk'::text
            ELSE 'healthy'::text
        END AS group_health_status
   FROM v_cencom_td_vacancies
  GROUP BY group_id, group_name, group_code
  ORDER BY group_code;

GRANT ALL ON public.v_cencom_td_by_group TO authenticated, postgres, service_role;


-- ── v_cencom_td_priority_queue (depends on v_cencom_td_vacancies) ───────────
CREATE OR REPLACE VIEW public.v_cencom_td_priority_queue AS
 SELECT vacancy_id,
    vcode,
    account,
    account_id,
    group_name,
    group_code,
    "position",
    area_name,
    store_name,
    vacant_date,
    vacancy_type,
    urgency_level,
    target_fill_date,
    required_headcount,
    aging_days,
    aging_bucket,
    priority_score,
    account_mfr,
    account_health_tier,
    urgency_tier
   FROM v_cencom_td_vacancies
  WHERE NOT is_advance_vacancy
  ORDER BY priority_score DESC, aging_days DESC NULLS LAST, vcode;

GRANT ALL ON public.v_cencom_td_priority_queue TO authenticated, postgres, service_role;


-- ── v_cencom_td_summary (depends on v_cencom_td_vacancies) ──────────────────
CREATE OR REPLACE VIEW public.v_cencom_td_summary AS
 SELECT count(*) FILTER (WHERE NOT is_advance_vacancy) AS operational_total,
    count(*) FILTER (WHERE is_advance_vacancy) AS advance_count,
    count(*) AS grand_total,
    count(*) FILTER (WHERE aging_bucket = '1_15'::text) AS bucket_1_15,
    count(*) FILTER (WHERE aging_bucket = '16_30'::text) AS bucket_16_30,
    count(*) FILTER (WHERE aging_bucket = '31_60'::text) AS bucket_31_60,
    count(*) FILTER (WHERE aging_bucket = '61_120'::text) AS bucket_61_120,
    count(*) FILTER (WHERE aging_bucket = 'gt121'::text) AS bucket_gt121,
    count(*) FILTER (WHERE urgency_tier = 'immediate'::text) AS urgency_immediate,
    count(*) FILTER (WHERE urgency_tier = 'critical'::text) AS urgency_critical,
    count(*) FILTER (WHERE urgency_tier = 'elevated'::text) AS urgency_elevated,
    count(*) FILTER (WHERE urgency_tier = 'normal'::text) AS urgency_normal,
    count(*) FILTER (WHERE NOT is_advance_vacancy AND account_health_tier = 'critical'::text) AS health_critical_count,
    count(*) FILTER (WHERE NOT is_advance_vacancy AND account_health_tier = 'at_risk'::text) AS health_at_risk_count,
    count(*) FILTER (WHERE NOT is_advance_vacancy AND (account_health_tier = ANY (ARRAY['elevated'::text, 'healthy'::text]))) AS health_ok_count,
    max(aging_days) AS max_aging_days,
    round(avg(aging_days), 1) AS avg_aging_days,
    round(count(*) FILTER (WHERE NOT is_advance_vacancy AND COALESCE(aging_days, 0) >= 31)::numeric * 100.0 / NULLIF(count(*) FILTER (WHERE NOT is_advance_vacancy), 0)::numeric, 1) AS pct_critical_aging,
    now() AS computed_at
   FROM v_cencom_td_vacancies;

GRANT ALL ON public.v_cencom_td_summary TO authenticated, postgres, service_role;


-- ── trg_auto_create_vacancy_slot (restored with original definition) ─────────
CREATE TRIGGER trg_auto_create_vacancy_slot
AFTER INSERT OR UPDATE OF status, required_headcount
ON public.vacancies
FOR EACH ROW EXECUTE FUNCTION fn_trg_auto_create_vacancy_slot();


-- ============================================================================
-- §6  Validation block — RAISE NOTICE assertions
--     Run output is the SQL validation output deliverable for OHM2026_0076B.
-- ============================================================================
DO $$
DECLARE
  v_count               int;
  v_hc_0064             numeric;
  v_hc_0065             numeric;
  v_active_esa_inactive int;
  v_inflated_vacancies  int;
BEGIN
  -- ── A. 2023-09515 vacancy HC ──────────────────────────────────────────────
  SELECT required_headcount INTO v_hc_0064
    FROM public.vacancies
   WHERE vcode = 'VMRIZG1_0064'
     AND is_archived = false
     AND status IN ('Open', 'Pipeline')
   ORDER BY updated_at DESC LIMIT 1;

  SELECT required_headcount INTO v_hc_0065
    FROM public.vacancies
   WHERE vcode = 'VMRIZG1_0065'
     AND is_archived = false
     AND status IN ('Open', 'Pipeline')
   ORDER BY updated_at DESC LIMIT 1;

  RAISE NOTICE '[OHM2026_0076B] VMRIZG1_0064 required_headcount = % (expected 0.5)', v_hc_0064;
  RAISE NOTICE '[OHM2026_0076B] VMRIZG1_0065 required_headcount = % (expected 0.5)', v_hc_0065;

  -- ── B. 2023-09515 active ESA count (expect 0 after backfill) ──────────────
  SELECT count(*) INTO v_count
    FROM public.employee_store_allocations esa
    JOIN public.plantilla p ON p.id = esa.plantilla_id
   WHERE p.employee_no = '2023-09515'
     AND esa.is_active = true;

  RAISE NOTICE '[OHM2026_0076B] 2023-09515 active ESA rows = % (expected 0)', v_count;

  -- ── C. Global: inactive employees with active ESA (expect 0) ──────────────
  SELECT count(*) INTO v_active_esa_inactive
    FROM public.employee_store_allocations esa
   WHERE esa.is_active = true
     AND EXISTS (
       SELECT 1 FROM public.plantilla p
        WHERE p.id = esa.plantilla_id
          AND p.is_deleted = false
          AND p.status NOT IN (
            'Active', 'For Deactivation', 'On Leave',
            'Pending Deactivation', 'Rejected Deactivation'
          )
     );

  RAISE NOTICE '[OHM2026_0076B] Inactive employees with active ESA rows = % (expected 0)', v_active_esa_inactive;

  -- ── D. Global: Open/Pipeline vacancies with inflated HC vs ESA (expect 0) ──
  SELECT count(*) INTO v_inflated_vacancies
    FROM public.vacancies v
    JOIN (
      SELECT DISTINCT ON (vcode) vcode, filled_hc
        FROM public.employee_store_allocations WHERE true AND filled_hc IS NOT NULL
         AND filled_hc > 0 AND filled_hc < 1
       ORDER BY vcode, created_at DESC
    ) ef ON ef.vcode = v.vcode
   WHERE v.status IN ('Open', 'Pipeline')
     AND v.is_archived = false
     AND v.deleted_at IS NULL
     AND v.required_headcount > ef.filled_hc;

  RAISE NOTICE '[OHM2026_0076B] Open/Pipeline vacancies with inflated HC vs ESA = % (expected 0)', v_inflated_vacancies;

  -- ── E. Sanity: stationary vacancies unaffected (required_headcount = 1) ───
  SELECT count(*) INTO v_count
    FROM public.vacancies v
   WHERE v.status IN ('Open', 'Pipeline')
     AND v.is_archived = false
     AND v.deleted_at IS NULL
     AND v.required_headcount = 1
     AND NOT EXISTS (
       SELECT 1 FROM public.employee_store_allocations esa
        WHERE esa.vcode = v.vcode
          AND esa.filled_hc IS NOT NULL
          AND esa.filled_hc < 1
     );

  RAISE NOTICE '[OHM2026_0076B] Stationary/normal Open vacancies (HC=1, no fractional ESA) = % (sanity, expect > 0)', v_count;

  -- ── F. Column type sanity check ───────────────────────────────────────────
  RAISE NOTICE '[OHM2026_0076B] required_headcount column type = % (expected numeric)',
    (SELECT data_type FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'vacancies'
        AND column_name = 'required_headcount');
END;
$$;

COMMIT;
