-- =============================================================================
-- Migration: 20260521200000_vcode_duplicate_cleanup.sql
-- Date:      2026-05-21
-- Phase:     VCODE Integrity — Duplicate VCODE Cleanup Rules (OHM2026_2012)
-- Extends:   20260519210000_fix_duplicate_plantilla_hr_emploc_id.sql
-- =============================================================================
--
-- Background
-- ----------
-- The existing guard migration (OHM2026_1044) prevents duplicate hr_emploc_id
-- values in active plantilla rows. This migration extends VCODE integrity by
-- addressing the lifecycle gap where a vacancy is not properly closed when an
-- employee completes the HR Emploc → Plantilla transition.
--
-- The core problem: move_to_plantilla closes the vacancy via hr_emploc.vacancy_id.
-- If vacancy_id is NULL on the hr_emploc row (created without a direct vacancy
-- link), the UPDATE vacancies SET status='Filled' step is silently skipped.
-- This leaves the vacancy Open with an Active Plantilla employee on the same
-- VCODE, causing:
--   (a) incorrect open_hc in v_workforce_health_summary (MFR double-count)
--   (b) the vacancy appearing live in the Vacancy Module when it is already filled
--
-- Cleanup Rule Summary
-- --------------------
-- Rule 1  Active Plantilla employee + same VCODE vacancy still Open/For Sourcing
--         → set vacancy status to 'Filled' (slot was filled; not archived).
-- Rule 2  HR Emploc status 'Moved to Plantilla' + same VCODE vacancy still Open
--         and no Active Plantilla row yet (transition gap)
--         → set vacancy status to 'Filled'.
-- Rule 3  True duplicate vacancy rows per VCODE are impossible:
--         vacancies_vcode_key UNIQUE (unconditional) prevents them at the DB
--         level. No action required.
-- Rule 4  HC Request auto-created Inactive Plantilla slot + Open vacancy,
--         same VCODE, from the same HC Request
--         → EXPECTED. Do NOT touch. MFR counts correctly (open_hc only,
--         slot is Inactive). Plantilla Vacancy Tab and Vacancy Module visibility
--         are preserved. Only the vacancy's status is changed when the employee
--         actually moves to Plantilla — not before.
-- Rule 5  Multiple Active Plantilla employees for the same VCODE
--         → CRITICAL DATA ISSUE. Do NOT auto-delete in this migration.
--         WARN with exact IDs. Manual cleanup SQL provided in comments below.
-- Rule 6  Archive-first. We use status='Filled' (not 'Archived') for closed
--         vacancies where the slot was actually filled. Hard delete is NOT
--         performed. FK dependencies are intact.
--
-- Steps in this migration
-- -----------------------
-- STEP 1  AUDIT       — Read-only diagnostic report (RAISE NOTICE / WARNING)
-- STEP 2  CLEANUP     — Archive/fix orphaned Open vacancies (Rules 1 & 2)
-- STEP 3  GUARD       — Trigger: auto-close vacancy by VCODE on Active plantilla INSERT
-- STEP 4  RPC FIX     — move_to_plantilla: VCODE-based vacancy fallback for all paths
--
-- Rollback notes
-- --------------
-- STEP 2:  UPDATE vacancies SET status='Filled'. Reversible by setting status
--          back to 'Open' for any incorrectly closed row. Use the STEP 1 audit
--          RAISE NOTICE output to identify affected vacancy IDs before applying.
-- STEP 3:  DROP TRIGGER tg_close_vacancy_on_plantilla_active_insert ON plantilla.
-- STEP 4:  Re-apply 20260519210000_fix_duplicate_plantilla_hr_emploc_id.sql to
--          restore the previous move_to_plantilla version without the VCODE fallback.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: AUDIT — VCODE integrity diagnostic (read-only)
--
-- Run this BEFORE applying STEP 2 to inspect what will be changed.
-- All output appears in the PostgreSQL log / migration run output.
--
-- 1a  Rule 5 (CRITICAL): Multiple Active Plantilla employees per VCODE.
-- 1b  Rule 1: Open vacancy + Active Plantilla employee, same VCODE.
--     (HC Request Inactive-slot pairs excluded — those are Rule 4.)
-- 1c  Rule 2: Open vacancy + HR Emploc 'Moved to Plantilla', same VCODE,
--     no Active Plantilla row (transition gap only).
-- 1d  Rule 4 (INFO): HC Request Inactive slot + Open vacancy, same VCODE.
--     Expected pairs. Reported for awareness only.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  r             record;
  v_rule5_count integer := 0;
  v_rule1_count integer := 0;
  v_rule2_count integer := 0;
  v_rule4_count integer := 0;
BEGIN

  -- ── 1a. Rule 5 — Multiple Active Plantilla employees per VCODE (CRITICAL) ──
  FOR r IN
    SELECT
      p.vcode,
      count(*)                                   AS active_count,
      string_agg(p.id::text,        ', ')        AS plantilla_ids,
      string_agg(p.employee_no,     ', ')        AS employee_nos,
      string_agg(p.employee_name,   ', ')        AS employee_names,
      string_agg(p.account,         ', ')        AS accounts,
      string_agg(COALESCE(p.hr_emploc_id::text, 'NULL'), ', ') AS hr_emploc_ids,
      min(p.created_at)                          AS earliest_created
    FROM public.plantilla p
    WHERE p.status                    = 'Active'
      AND COALESCE(p.is_deleted, false) = false
      AND p.vcode IS NOT NULL
    GROUP BY p.vcode
    HAVING count(*) > 1
    ORDER BY count(*) DESC
  LOOP
    v_rule5_count := v_rule5_count + 1;
    RAISE WARNING
      '[RULE 5 CRITICAL] Multiple Active Plantilla employees on VCODE=%: '
      'active_count=% | plantilla_ids=[%] | employee_nos=[%] | '
      'employee_names=[%] | accounts=[%] | hr_emploc_ids=[%]',
      r.vcode, r.active_count, r.plantilla_ids,
      r.employee_nos, r.employee_names, r.accounts, r.hr_emploc_ids;
  END LOOP;

  IF v_rule5_count > 0 THEN
    RAISE WARNING
      '[RULE 5] % VCODE(s) have multiple Active Plantilla employees. '
      'This migration does NOT auto-delete any of them. '
      'Resolve manually using the Rule 5 cleanup SQL in the migration comments.',
      v_rule5_count;
  ELSE
    RAISE NOTICE '[RULE 5 OK] No VCODE has multiple Active Plantilla employees.';
  END IF;

  -- ── 1b. Rule 1 — Open vacancy + Active Plantilla employee, same VCODE ──────
  --        Excludes HC Request Inactive-slot pairs (those are Rule 4).
  FOR r IN
    SELECT
      v.id         AS vacancy_id,
      v.vcode,
      v.status     AS vacancy_status,
      v.account    AS vacancy_account,
      p.id         AS plantilla_id,
      p.employee_no,
      p.employee_name,
      p.hr_emploc_id
    FROM public.vacancies v
    JOIN public.plantilla p
      ON  p.vcode  = v.vcode
      AND p.status = 'Active'
      AND COALESCE(p.is_deleted, false) = false
    WHERE v.status IN ('Open', 'For Sourcing')
      AND COALESCE(v.is_archived, false) = false
      AND v.deleted_at IS NULL
      -- Exclude HC Request slot+vacancy pairs (Rule 4):
      -- source_plantilla_id points to an Inactive slot with the same VCODE.
      AND NOT EXISTS (
        SELECT 1
          FROM public.plantilla slot
         WHERE slot.id     = v.source_plantilla_id
           AND slot.vcode  = v.vcode
           AND slot.status = 'Inactive'
           AND COALESCE(slot.is_deleted, false) = false
      )
    ORDER BY v.vcode
  LOOP
    v_rule1_count := v_rule1_count + 1;
    RAISE NOTICE
      '[RULE 1] Orphaned Open vacancy: vcode=% | vacancy_id=% | '
      'vacancy_status=% | account=% | plantilla_id=% | employee_no=% | hr_emploc_id=%',
      r.vcode, r.vacancy_id, r.vacancy_status, r.vacancy_account,
      r.plantilla_id, r.employee_no, r.hr_emploc_id;
  END LOOP;

  IF v_rule1_count > 0 THEN
    RAISE NOTICE
      '[RULE 1] % orphaned Open vacancy row(s) detected. '
      'STEP 2 will set them to Filled.',
      v_rule1_count;
  ELSE
    RAISE NOTICE '[RULE 1 OK] No orphaned Open vacancies found for Active Plantilla VCODEs.';
  END IF;

  -- ── 1c. Rule 2 — HR Emploc 'Moved to Plantilla' + Open vacancy, ────────────
  --        no Active Plantilla row yet (transition gap only; avoids double-report)
  FOR r IN
    SELECT
      v.id             AS vacancy_id,
      v.vcode,
      v.account        AS vacancy_account,
      he.id            AS hr_emploc_id,
      he.applicant_name,
      he.moved_to_plantilla_at
    FROM public.vacancies v
    JOIN public.hr_emploc he
      ON  he.vcode  = v.vcode
      AND he.status = 'Moved to Plantilla'
      AND he.deleted_at IS NULL
    WHERE v.status IN ('Open', 'For Sourcing')
      AND COALESCE(v.is_archived, false) = false
      AND v.deleted_at IS NULL
      -- Only report if no Active Plantilla employee exists (avoids Rule 1 overlap)
      AND NOT EXISTS (
        SELECT 1
          FROM public.plantilla p2
         WHERE p2.vcode  = v.vcode
           AND p2.status = 'Active'
           AND COALESCE(p2.is_deleted, false) = false
      )
    ORDER BY v.vcode
  LOOP
    v_rule2_count := v_rule2_count + 1;
    RAISE NOTICE
      '[RULE 2] Vacancy open after HR Emploc Moved to Plantilla: '
      'vcode=% | vacancy_id=% | account=% | hr_emploc_id=% | applicant=% | moved_at=%',
      r.vcode, r.vacancy_id, r.vacancy_account,
      r.hr_emploc_id, r.applicant_name, r.moved_to_plantilla_at;
  END LOOP;

  IF v_rule2_count > 0 THEN
    RAISE NOTICE
      '[RULE 2] % vacancy row(s) detected. STEP 2 will set them to Filled.',
      v_rule2_count;
  ELSE
    RAISE NOTICE '[RULE 2 OK] No open vacancies with Moved-to-Plantilla HR Emploc found.';
  END IF;

  -- ── 1d. Rule 4 (INFO) — HC Request Inactive slot + Open vacancy ─────────────
  FOR r IN
    SELECT
      v.id       AS vacancy_id,
      v.vcode,
      v.account  AS vacancy_account,
      p.id       AS plantilla_slot_id,
      p.source_headcount_request_id
    FROM public.vacancies v
    JOIN public.plantilla p
      ON  p.id     = v.source_plantilla_id
      AND p.vcode  = v.vcode
      AND p.status = 'Inactive'
      AND COALESCE(p.is_deleted, false) = false
    WHERE v.status IN ('Open', 'For Sourcing')
      AND COALESCE(v.is_archived, false) = false
      AND v.deleted_at IS NULL
    ORDER BY v.vcode
  LOOP
    v_rule4_count := v_rule4_count + 1;
    RAISE NOTICE
      '[RULE 4 EXPECTED] HC Request vacant slot + Open vacancy (same VCODE): '
      'vcode=% | vacancy_id=% | plantilla_slot_id=% | request_id=%. '
      'No action. MFR counts once (open_hc). Plantilla Vacancy Tab preserved.',
      r.vcode, r.vacancy_id, r.plantilla_slot_id, r.source_headcount_request_id;
  END LOOP;

  RAISE NOTICE
    '[RULE 4] % HC Request slot+vacancy pair(s) found. All are expected.',
    v_rule4_count;

END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: CLEANUP — Fix orphaned Open vacancies (Rules 1 & 2)
--
-- Both rules set vacancy status to 'Filled' (not 'Archived') because the slot
-- was filled by an employee; 'Archived' is reserved for manually closed,
-- unfilled slots.
--
-- Setting status='Filled' removes the vacancy from:
--   - open_hc in v_workforce_health_summary (MFR fix)
--   - Vacancy Module Open/For Sourcing lists (visibility fix)
--   - required_hc double-count (required_hc = active_hc + open_hc)
--
-- The Plantilla Vacancy Tab (Inactive slot rows in plantilla) is NOT affected
-- by this step. Only vacancy rows are updated here.
--
-- Safety constraints applied:
--   - Only vacancies WHERE status IN ('Open', 'For Sourcing')
--   - Only vacancies WHERE NOT is_archived AND deleted_at IS NULL
--   - HC Request slot+vacancy pairs are excluded by source_plantilla_id guard
--   - FOR UPDATE locking to prevent concurrent modification races
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  r             record;
  v_rule1_fixed integer := 0;
  v_rule2_fixed integer := 0;
BEGIN

  -- ── Rule 1: Close vacancies orphaned after Plantilla move ───────────────────
  FOR r IN
    SELECT v.id, v.vcode, v.account, v.status AS old_status
    FROM public.vacancies v
    WHERE v.status IN ('Open', 'For Sourcing')
      AND COALESCE(v.is_archived, false) = false
      AND v.deleted_at IS NULL
      AND EXISTS (
        SELECT 1
          FROM public.plantilla p
         WHERE p.vcode  = v.vcode
           AND p.status = 'Active'
           AND COALESCE(p.is_deleted, false) = false
      )
      -- Exclude HC Request slot+vacancy pairs (Rule 4)
      AND NOT EXISTS (
        SELECT 1
          FROM public.plantilla slot
         WHERE slot.id     = v.source_plantilla_id
           AND slot.vcode  = v.vcode
           AND slot.status = 'Inactive'
           AND COALESCE(slot.is_deleted, false) = false
      )
    ORDER BY v.vcode
    FOR UPDATE
  LOOP
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW()
     WHERE id = r.id;

    v_rule1_fixed := v_rule1_fixed + 1;
    RAISE NOTICE
      '[RULE 1 FIX] vacancy_id=% vcode=% account=% | % → Filled',
      r.id, r.vcode, r.account, r.old_status;
  END LOOP;

  RAISE NOTICE '[RULE 1] Fixed % orphaned Open vacancy row(s).', v_rule1_fixed;

  -- ── Rule 2: Close vacancies where HR Emploc is Moved to Plantilla ───────────
  --    Only where no Active Plantilla employee exists yet (transition gap).
  FOR r IN
    SELECT v.id, v.vcode, v.account, v.status AS old_status
    FROM public.vacancies v
    WHERE v.status IN ('Open', 'For Sourcing')
      AND COALESCE(v.is_archived, false) = false
      AND v.deleted_at IS NULL
      AND EXISTS (
        SELECT 1
          FROM public.hr_emploc he
         WHERE he.vcode  = v.vcode
           AND he.status = 'Moved to Plantilla'
           AND he.deleted_at IS NULL
      )
      AND NOT EXISTS (
        SELECT 1
          FROM public.plantilla p2
         WHERE p2.vcode  = v.vcode
           AND p2.status = 'Active'
           AND COALESCE(p2.is_deleted, false) = false
      )
    ORDER BY v.vcode
    FOR UPDATE
  LOOP
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW()
     WHERE id = r.id;

    v_rule2_fixed := v_rule2_fixed + 1;
    RAISE NOTICE
      '[RULE 2 FIX] vacancy_id=% vcode=% account=% | % → Filled',
      r.id, r.vcode, r.account, r.old_status;
  END LOOP;

  RAISE NOTICE '[RULE 2] Fixed % vacancy row(s) from HR Emploc transition gap.', v_rule2_fixed;

END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: GUARD — Trigger: auto-close vacancy by VCODE on Active plantilla INSERT
--
-- Purpose:
--   Belt-and-suspenders prevention of Rule 1 reoccurrence. When an Active
--   Plantilla employee is inserted (any path: stationary / roving / pool),
--   this trigger closes any Open/For Sourcing vacancy with the same VCODE.
--
-- Design decisions:
--   - Fires AFTER INSERT only (not UPDATE/DELETE) — the critical moment is
--     when a new Active employee row is committed to plantilla.
--   - Guards on NEW.status = 'Active' AND NEW.vcode IS NOT NULL — harmless
--     no-op for Inactive slots (HC Request pattern), roving masters (vcode=NULL),
--     deactivated rows, or any other non-Active status.
--   - HC Request Inactive slot safety: the trigger only fires for Active inserts.
--     An HC Request creates an Inactive slot (NEW.status='Inactive') — the guard
--     prevents the trigger from running for that insert. When the employee later
--     moves to Plantilla (new Active INSERT), the trigger correctly closes the
--     now-stale Open vacancy. The Inactive slot row is preserved in plantilla for
--     Plantilla Vacancy Tab visibility.
--   - Idempotent: the WHERE status IN ('Open','For Sourcing') condition ensures
--     a second trigger fire on the same vcode is a no-op.
--   - No updated_by set (system trigger, no user actor available at this level).
--
-- Rollback:
--   DROP TRIGGER tg_close_vacancy_on_plantilla_active_insert ON public.plantilla;
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.tg_close_vacancy_on_plantilla_active_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Only act on Active employees with a VCODE
  IF NEW.status <> 'Active' OR NEW.vcode IS NULL THEN
    RETURN NEW;
  END IF;

  -- Close any Open/For Sourcing vacancy with the same VCODE.
  -- The HC Request Inactive slot pattern is excluded naturally:
  -- this trigger only fires for Active inserts, not Inactive slot inserts.
  -- When the employee IS being placed (Active insert), setting the vacancy
  -- to Filled is the correct outcome regardless of HC Request origin.
  UPDATE public.vacancies
     SET status     = 'Filled',
         updated_at = NOW()
   WHERE vcode      = NEW.vcode
     AND status     IN ('Open', 'For Sourcing')
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.tg_close_vacancy_on_plantilla_active_insert() IS
  'VCODE integrity guard: fires AFTER INSERT on plantilla for Active rows. '
  'Closes any Open/For Sourcing vacancy with the same VCODE. '
  'Belt-and-suspenders backstop for move_to_plantilla VCODE fallback. '
  'Idempotent. Does not fire for Inactive slots, roving masters (vcode=NULL), '
  'or non-Active status inserts.';

DROP TRIGGER IF EXISTS tg_close_vacancy_on_plantilla_active_insert
  ON public.plantilla;

CREATE TRIGGER tg_close_vacancy_on_plantilla_active_insert
  AFTER INSERT ON public.plantilla
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_close_vacancy_on_plantilla_active_insert();


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: RPC FIX — move_to_plantilla: VCODE-based vacancy fallback
--
-- Problem:
--   The existing RPC closes the vacancy via hr_emploc.vacancy_id:
--     UPDATE vacancies SET status='Filled' WHERE id = v_emp.vacancy_id
--   If vacancy_id IS NULL on the hr_emploc row, this UPDATE is skipped
--   (guarded by IF v_emp.vacancy_id IS NOT NULL). The vacancy remains Open.
--
-- Fix:
--   After each path's vacancy_id-based closure, add a VCODE-based fallback:
--     UPDATE vacancies SET status='Filled' WHERE vcode = v_emp.vcode
--       AND status IN ('Open','For Sourcing') AND NOT is_archived
--   This closes any remaining Open vacancy for the VCODE regardless of
--   whether vacancy_id was set on the hr_emploc.
--
-- Idempotency:
--   The WHERE status IN ('Open','For Sourcing') guard ensures a double-call
--   is a safe no-op. Guards A and B on hr_emploc_id and moved_to_plantilla_at
--   prevent the plantilla INSERT from running twice. If the INSERT is blocked,
--   the VCODE fallback UPDATE is never reached.
--
-- Plantilla Vacancy Tab / HC Request safety:
--   When move_to_plantilla runs for an HC Request slot, the VCODE fallback
--   correctly sets the HC Request vacancy to 'Filled'. The Inactive plantilla
--   slot (from the HC Request) is preserved in plantilla and continues to be
--   visible in the Plantilla Vacancy Tab. The Vacancy Module shows the vacancy
--   as Filled — correct behavior.
--
-- Changes from 20260519210000_fix_duplicate_plantilla_hr_emploc_id.sql:
--   + VCODE fallback UPDATE after vacancy_id-based closure in all three paths.
--   All other logic is verbatim from the previous migration.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.move_to_plantilla(p_id uuid)
RETURNS public.plantilla
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_emp             public.hr_emploc;
  v_pl              public.plantilla;
  v_actor           uuid := get_my_profile_id();
  v_is_pool         boolean := false;
  v_pool_type_id    uuid;
  v_home_account_id uuid;
  v_home_acct       public.accounts;
BEGIN
  -- Data Team = Encoder + Head Admin + Super Admin
  IF NOT (i_have_full_access() OR get_my_role() = 'Encoder') THEN
    RAISE EXCEPTION 'forbidden: Data Team role required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_emp FROM hr_emploc WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or archived', p_id USING ERRCODE = 'P0002';
  END IF;
  IF v_emp.status <> 'Ready for Plantilla' THEN
    RAISE EXCEPTION 'cannot move: status is "%", expected "Ready for Plantilla"', v_emp.status
      USING ERRCODE = '22023';
  END IF;
  IF v_emp.employee_no IS NULL THEN
    RAISE EXCEPTION 'cannot move: employee_no is null' USING ERRCODE = '22023';
  END IF;

  -- Guard A: hr_emploc_id already active in plantilla
  IF EXISTS (
    SELECT 1
      FROM public.plantilla
     WHERE hr_emploc_id         = p_id
       AND COALESCE(is_deleted, false) = false
  ) THEN
    RAISE EXCEPTION 'hr_emploc % already moved to plantilla', p_id USING ERRCODE = '23505';
  END IF;

  -- Guard B: moved_to_plantilla_at already stamped
  IF v_emp.moved_to_plantilla_at IS NOT NULL THEN
    RAISE EXCEPTION
      'hr_emploc % already has moved_to_plantilla_at set', p_id USING ERRCODE = '23505';
  END IF;

  -- Detect pool vacancy
  IF v_emp.vacancy_id IS NOT NULL THEN
    SELECT v.is_pool_vacancy, v.pool_type_id, v.home_account_id
      INTO v_is_pool, v_pool_type_id, v_home_account_id
      FROM vacancies v
     WHERE v.id = v_emp.vacancy_id;
  END IF;
  v_is_pool := COALESCE(v_is_pool, false);

  -- ── POOL PATH ───────────────────────────────────────────────────────────────
  IF v_is_pool THEN

    IF v_home_account_id IS NULL THEN
      RAISE EXCEPTION 'pool vacancy % has no home_account_id — cannot route to pool',
        v_emp.vcode USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_home_acct FROM accounts WHERE id = v_home_account_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'home account % not found', v_home_account_id USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (
      SELECT 1 FROM plantilla
       WHERE employee_no = v_emp.employee_no
         AND account_id  = v_home_account_id
         AND is_deleted  = false
         AND status IN ('Active', 'For Deactivation', 'On Leave')
    ) THEN
      RAISE EXCEPTION
        'pool plantilla already has active record for employee_no % under home account',
        v_emp.employee_no USING ERRCODE = '23505';
    END IF;

    INSERT INTO plantilla (
      account,              account_id,
      store_id,             store_name,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,          pagibig_no,
      date_hired,           vacancy_id,              vacancy_code_snapshot,
      vcode,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      is_pool_employee,     pool_type_id,
      requesting_account,   requesting_account_id,   requesting_store_id,
      status,               tagged_at,
      moved_by_user_id,     created_by,              updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_home_acct.account_name, v_home_acct.id,
      NULL, NULL,
      v_emp.position,           v_emp.position_id_snapshot,
      v_emp.employee_no,        v_emp.employee_no,
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot,       v_emp.philhealth_snapshot,    v_emp.pagibig_snapshot,
      v_emp.hired_date,         v_emp.vacancy_id,             v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name,          v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot,  v_emp.area_name_snapshot,
      v_emp.id,
      true,                     v_pool_type_id,
      v_emp.account,            v_emp.account_id,             v_emp.store_id,
      'Active',                 CURRENT_DATE,
      v_actor, v_actor, v_actor,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    -- Close via vacancy_id if available
    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE id = v_emp.vacancy_id;
    END IF;

    -- ── VCODE fallback: close any remaining Open vacancy for this VCODE ──────
    -- Covers the vacancy_id=NULL gap. Idempotent when vacancy already Filled.
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL;

    -- Mark pool slot occupied
    UPDATE public.workforce_pool_slots
       SET status     = 'filled',
           updated_at = NOW()
     WHERE vcode      = v_emp.vcode
       AND deleted_at IS NULL;

  -- ── ROVING PATH ─────────────────────────────────────────────────────────────
  ELSIF v_emp.assignment_type = 'Roving' THEN

    IF EXISTS (
      SELECT 1 FROM plantilla
       WHERE roving_assignment_id = v_emp.roving_assignment_id
         AND is_deleted = false
    ) THEN
      RAISE EXCEPTION
        'roving plantilla master already exists for roving_assignment_id %. '
        'Use link_late_store_to_plantilla for new store additions.',
        v_emp.roving_assignment_id USING ERRCODE = '23505';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM hr_emploc_store_links
       WHERE hr_emploc_id = p_id
         AND status       = 'Confirmed'
         AND deleted_at   IS NULL
    ) THEN
      RAISE EXCEPTION 'no confirmed store links found for roving hr_emploc %', p_id
        USING ERRCODE = '22023';
    END IF;

    INSERT INTO plantilla (
      account,              account_id,           chain_id,             province_id,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,         pagibig_no,
      date_hired,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      roving_assignment_id,
      deployment_type,
      status,               tagged_at,
      moved_by_user_id,     created_by,            updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_emp.account, v_emp.account_id, v_emp.chain_id, v_emp.province_id,
      v_emp.position, v_emp.position_id_snapshot,
      v_emp.employee_no, v_emp.employee_no,
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot, v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date,
      v_emp.hrco_name, v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      v_emp.roving_assignment_id,
      'Roving',
      'Active', CURRENT_DATE,
      v_actor, v_actor, v_actor,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    INSERT INTO public.plantilla_store_links (
      plantilla_id,
      roving_assignment_id,
      hr_emploc_store_link_id,
      vacancy_id,
      vcode,
      store_name,
      account,
      status,
      linked_at,
      linked_by,
      created_by,
      updated_by
    )
    SELECT
      v_pl.id,
      sl.roving_assignment_id,
      sl.id,
      sl.vacancy_id,
      sl.vcode,
      sl.store_name,
      sl.account,
      'Active',
      NOW(),
      v_actor,
      v_actor,
      v_actor
    FROM public.hr_emploc_store_links sl
    WHERE sl.hr_emploc_id = p_id
      AND sl.status       = 'Confirmed'
      AND sl.deleted_at   IS NULL;

    -- Close confirmed store vacancies via vacancy_id
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE id IN (
       SELECT vacancy_id
         FROM public.hr_emploc_store_links
        WHERE hr_emploc_id = p_id
          AND status       = 'Confirmed'
          AND deleted_at   IS NULL
          AND vacancy_id   IS NOT NULL
     )
     AND status NOT IN ('Filled', 'Closed', 'Archived');

    -- ── VCODE fallback: close any remaining Open vacancy for the roving VCODE ─
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL;

  -- ── STATIONARY PATH ─────────────────────────────────────────────────────────
  ELSE

    IF EXISTS (
      SELECT 1 FROM plantilla
       WHERE employee_no = v_emp.employee_no
         AND is_deleted  = false
         AND status IN ('Active', 'For Deactivation', 'On Leave')
    ) THEN
      RAISE EXCEPTION 'plantilla already has active record for employee_no %',
        v_emp.employee_no USING ERRCODE = '23505';
    END IF;

    INSERT INTO plantilla (
      account,              account_id,            chain_id,             store_id,
      store_name,           position,              position_id,
      province_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,          pagibig_no,
      date_hired,           vacancy_id,              vacancy_code_snapshot,
      vcode,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      status,               tagged_at,
      moved_by_user_id,     created_by,              updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_emp.account,        v_emp.account_id,       v_emp.chain_id,       v_emp.store_id,
      v_emp.store_name,     v_emp.position,         v_emp.position_id_snapshot,
      v_emp.province_id,
      v_emp.employee_no,    v_emp.employee_no,
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot,   v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date,     v_emp.vacancy_id,        v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name,      v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      'Active',             CURRENT_DATE,
      v_actor, v_actor, v_actor, NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    -- Close via vacancy_id if available
    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE id = v_emp.vacancy_id;
    END IF;

    -- ── VCODE fallback: close any remaining Open vacancy for this VCODE ──────
    -- Covers the vacancy_id=NULL gap. Idempotent when vacancy already Filled.
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL;

  END IF;

  -- ── Common: update hr_emploc status ─────────────────────────────────────────
  UPDATE hr_emploc
     SET status                = 'Moved to Plantilla',
         hr_status             = 'Transferred',
         moved_to_plantilla_at = NOW(),
         moved_to_plantilla_by = v_actor,
         updated_at            = NOW(),
         updated_by            = v_actor
   WHERE id = p_id;

  PERFORM log_audit_event('plantilla', 'INSERT', v_pl.id, NULL, to_jsonb(v_pl));
  PERFORM log_audit_event('hr_emploc', 'UPDATE', p_id, to_jsonb(v_emp),
                          to_jsonb((SELECT h FROM hr_emploc h WHERE h.id = p_id)));
  RETURN v_pl;
END
$$;

-- Re-apply grants after function recreation (idempotent)
REVOKE ALL ON FUNCTION public.move_to_plantilla(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.move_to_plantilla(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_to_plantilla(uuid) TO service_role;


-- =============================================================================
-- RULE 5 — Manual Cleanup SQL (do NOT run automatically)
--
-- Use the STEP 1 RAISE WARNING output to get the exact plantilla_ids,
-- employee_nos, and hr_emploc_ids for each affected VCODE, then run:
--
-- Step A: Inspect the duplicate pair
-- ---------------------------------------------------------------------------
-- SELECT
--   p.id, p.vcode, p.employee_no, p.employee_name, p.account,
--   p.status, p.hr_emploc_id, p.created_at, p.tagged_at,
--   he.status AS emploc_status, he.moved_to_plantilla_at
-- FROM public.plantilla p
-- LEFT JOIN public.hr_emploc he ON he.id = p.hr_emploc_id
-- WHERE p.vcode = '<AFFECTED_VCODE>'
--   AND p.status = 'Active'
--   AND COALESCE(p.is_deleted, false) = false
-- ORDER BY p.created_at;
--
-- Step B: Identify the legitimate record
-- ---------------------------------------------------------------------------
-- Keep the plantilla row that:
--   (a) has a valid hr_emploc_id linked to an hr_emploc in 'Moved to Plantilla'
--       state AND moved_to_plantilla_at IS NOT NULL, AND
--   (b) has the correct employee_no matching the actual deployed employee.
-- Soft-delete the duplicate row — do NOT hard delete.
--
-- Step C: Soft-delete the confirmed duplicate
-- ---------------------------------------------------------------------------
-- UPDATE public.plantilla
--    SET is_deleted         = true,
--        deletion_reason    = 'Rule 5 cleanup: duplicate VCODE active employee — '
--                             'confirmed duplicate per OHM2026_2012 audit',
--        deletion_requested_at = NOW(),
--        updated_at         = NOW()
--  WHERE id = '<DUPLICATE_PLANTILLA_ID>'
--    AND vcode = '<AFFECTED_VCODE>'
--    AND status = 'Active';
-- -- Verify only one active row remains:
-- SELECT count(*) FROM public.plantilla
--  WHERE vcode = '<AFFECTED_VCODE>' AND status = 'Active'
--    AND COALESCE(is_deleted, false) = false;
-- -- Expected: 1
--
-- Step D: If duplicate hr_emploc rows exist for the same VCODE
-- ---------------------------------------------------------------------------
-- SELECT id, applicant_name, vcode, status, employee_no, moved_to_plantilla_at,
--        deleted_at
--   FROM public.hr_emploc
--  WHERE vcode = '<AFFECTED_VCODE>'
--  ORDER BY created_at;
--
-- If a spurious hr_emploc row exists (not linked to the valid plantilla row),
-- archive it via fn_request_emploc_deletion with reason 'Duplicate Record'.
-- Do NOT set deleted_at directly — route through the deletion request workflow
-- to preserve audit trail and RBAC review.
--
-- =============================================================================


-- =============================================================================
-- Validation checklist (run after migration)
-- =============================================================================
-- 1. STEP 1 re-run: Rule 1 and Rule 2 NOTICE counts should be 0 after STEP 2.
-- 2. STEP 1 re-run: Rule 5 WARNINGs must be investigated manually — no auto-fix.
-- 3. Rule 4 INFO count should match pre-migration count (unchanged).
-- 4. move_to_plantilla: single move succeeds for stationary, roving, pool paths.
-- 5. move_to_plantilla: double-tap returns 23505; no duplicate plantilla row.
-- 6. move_to_plantilla: vacancy_id=NULL hr_emploc → vacancy still set to Filled.
-- 7. HC Request flow: submit_headcount_request still creates Inactive slot +
--    Open vacancy. Plantilla Vacancy Tab shows the slot. Vacancy Module shows Open.
-- 8. HC Request fill: after move_to_plantilla on the HC Request slot applicant,
--    vacancy changes to Filled. Inactive slot remains in plantilla (preserved).
-- 9. MFR: v_workforce_health_summary active_hc + open_hc no longer double-counts
--    VCODEs where Active employee + vacancy co-exist.
-- 10. Trigger: insert an Active plantilla row for a VCODE that has an Open
--     vacancy → vacancy must be Filled after insert.
-- 11. Trigger: insert an Inactive plantilla slot (HC Request) → Open vacancy
--     for that VCODE must remain Open (trigger must not fire for Inactive status).
-- =============================================================================
