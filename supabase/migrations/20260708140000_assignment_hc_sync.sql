-- Migration: 20260708140000_assignment_hc_sync
-- Prompt IDs: ohm#3bd81e6a (Flutter UI) + ohm#91c5af4e (Backend enforcement)
--
-- Purpose:
--   1. Add p_vacancy_requirement_id (uuid, DEFAULT NULL) to confirm_applicant_onboard.
--      When supplied: atomically increments hc_filled on the matching vacancy_requirements
--      row, guarded against overfill. When NULL: backward-compat fallback auto-selects
--      the first available requirement for the vacancy (silent no-op when no rows exist).
--
--   2. Add hc_filled decrement to fn_plantilla_separation_to_vacancy (stationary path)
--      so resigned/separated employees release their HC slot back to the requirement.
--
-- Backward compatibility contract:
--   - p_vacancy_requirement_id DEFAULT NULL — all existing callers unaffected.
--   - Existing GRANT on confirm_applicant_onboard preserved.
--   - Vacancies with no vacancy_requirements rows: NULL fallback UPDATE finds no rows,
--     raises no error (FOUND guard omitted on fallback — intentional silent no-op).
--   - Only the SECURITY DEFINER context (postgres, bypasses RLS) can write vacancy_requirements;
--     RLS remains read-only for authenticated per ohm#7f3a9c2d.
--
-- Depends on:
--   20260813000002_wire_pipeline_hr_processing_slot_transition.sql
--     (latest confirm_applicant_onboard body with 12 params: uuid..date)
--   20260916000000_fix_fractional_hc_vacancy_and_inactive_esa_cleanup.sql
--     (latest fn_plantilla_separation_to_vacancy body)
--   20260708012728_add_vacancy_requirements_normalization.sql
--     (vacancy_requirements table + trg_check_vr_capacity)
--
-- Validation queries at bottom of file.

-- ============================================================
-- §1  Patch confirm_applicant_onboard — add p_vacancy_requirement_id
-- ============================================================
--
-- Source base: 20260813000002 (12-arg signature ending in p_hired_date date)
-- This adds a 13th optional param. The old 12-arg overload is dropped to avoid
-- ambiguity (all callers are Flutter RPCs that pass named params; no code passes
-- exactly 12 positional args).

DROP FUNCTION IF EXISTS public.confirm_applicant_onboard(
  uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date
);

CREATE OR REPLACE FUNCTION public.confirm_applicant_onboard(
  p_applicant_id             uuid,
  p_last_name                text    DEFAULT NULL::text,
  p_first_name               text    DEFAULT NULL::text,
  p_middle_name              text    DEFAULT NULL::text,
  p_full_name                text    DEFAULT NULL::text,
  p_contact_number           text    DEFAULT NULL::text,
  p_remarks                  text    DEFAULT NULL::text,
  p_roving_assignment_id     uuid    DEFAULT NULL::uuid,
  p_hired_by_user_id         uuid    DEFAULT NULL::uuid,
  p_endorsed_by_deployer_id  uuid    DEFAULT NULL::uuid,
  p_endorsed_by_name         text    DEFAULT NULL::text,
  p_hired_date               date    DEFAULT NULL::date,
  -- ohm#3bd81e6a / ohm#91c5af4e: optional requirement line-item selection
  p_vacancy_requirement_id   uuid    DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role        text    := public.get_my_role();
  v_role_level  int     := COALESCE(public.get_my_role_level(), 0);
  v_profile_id  uuid    := public.get_my_profile_id();
  v_actor_name  text    := public.get_my_full_name();
  v_app         public.applicants%ROWTYPE;
  v_vac         public.vacancies%ROWTYPE;
  v_hr          public.hr_emploc%ROWTYPE;
  v_full_name   text;
  v_hired_by_id uuid;
  v_is_roving   boolean;
  v_store_link_id uuid;
  v_late_result   jsonb;
  -- fast-track vars
  v_existing_plt      public.plantilla%ROWTYPE;
  v_roving_id         uuid;
  v_new_roving        boolean := false;
  v_plt_store_link_id uuid;
  v_existing_employee_no text;
  v_roving_hr_found   boolean := false;
BEGIN
  -- ── RBAC ────────────────────────────────────────────────────────────────
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Data Team, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch and lock applicant ─────────────────────────────────────────────
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
  FOR UPDATE;

  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_app.status, 'New') IN (
    'Failed', 'Backout', 'Did Not Report', 'Rejected by Ops'
  ) THEN
    RAISE EXCEPTION
      'applicant % has terminal status % — cannot onboard',
      p_applicant_id, v_app.status
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Fetch vacancy ────────────────────────────────────────────────────────
  SELECT * INTO v_vac
    FROM public.vacancies
   WHERE vcode = v_app.vacancy_vcode
     AND deleted_at IS NULL
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'vacancy % not found', v_app.vacancy_vcode
      USING ERRCODE = 'P0002';
  END IF;

  v_is_roving := COALESCE(v_vac.is_roving, false);

  -- ── Resolve hired_by user ────────────────────────────────────────────────
  IF p_hired_by_user_id IS NOT NULL THEN
    v_hired_by_id := p_hired_by_user_id;
  ELSE
    v_hired_by_id := public.get_my_auth_uid();
  END IF;

  -- ── Update applicant fields ──────────────────────────────────────────────
  UPDATE public.applicants
     SET status             = 'Confirmed Onboard',
         last_name          = COALESCE(p_last_name,      last_name),
         first_name         = COALESCE(p_first_name,     first_name),
         middle_name        = COALESCE(p_middle_name,    middle_name),
         full_name          = COALESCE(p_full_name,      full_name),
         contact_number     = COALESCE(p_contact_number, contact_number),
         remarks            = COALESCE(p_remarks,        remarks),
         hired_date         = COALESCE(p_hired_date,     hired_date),
         hired_by           = v_hired_by_id::text,
         roving_assignment_id = COALESCE(
                                  p_roving_assignment_id,
                                  roving_assignment_id
                                ),
         last_activity_at   = NOW(),
         last_activity_by   = v_profile_id,
         updated_at         = NOW()
   WHERE id = p_applicant_id;

  -- Reload refreshed applicant
  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id;

  -- ── Roving assignment creation ───────────────────────────────────────────
  IF v_is_roving AND p_roving_assignment_id IS NULL THEN
    -- Look for existing roving assignment linked to the plantilla record
    SELECT ra.id INTO v_roving_id
      FROM public.plantilla plt
      JOIN public.roving_assignments ra
        ON ra.plantilla_id = plt.id AND ra.is_active = true
     WHERE plt.employee_no = v_app.full_name
       AND plt.account = v_vac.account
     LIMIT 1;

    IF v_roving_id IS NULL THEN
      v_new_roving := true;
    END IF;
  ELSE
    v_roving_id := p_roving_assignment_id;
  END IF;

  -- ── Fast-track path: existing Plantilla employee ────────────────────────
  -- Check if there's an existing active plantilla record for this person
  SELECT plt.* INTO v_existing_plt
    FROM public.plantilla plt
   WHERE plt.account = v_vac.account
     AND (
       plt.employee_no ILIKE v_app.full_name
       OR plt.employee_name ILIKE v_app.full_name
     )
     AND plt.status IN ('Active', 'On Leave')
     AND NOT COALESCE(plt.is_deleted, false)
     AND NOT COALESCE(plt.is_archived, false)
   LIMIT 1;

  IF v_existing_plt.id IS NOT NULL THEN
    -- Fast-track: link late store to existing plantilla (roving or stationary)
    v_late_result := public.link_late_store_to_plantilla(
      p_plantilla_id      => v_existing_plt.id,
      p_vcode             => v_vac.vcode,
      p_vacancy_id        => v_vac.id,
      p_applicant_id      => v_app.id,
      p_performed_by      => v_profile_id
    );
  END IF;

  -- ── HR Emploc record ─────────────────────────────────────────────────────
  -- Always create/update hr_emploc (even on fast-track; acts as audit trail)
  SELECT * INTO v_hr
    FROM public.hr_emploc
   WHERE applicant_id = p_applicant_id
   LIMIT 1;

  IF v_hr.id IS NOT NULL THEN
    -- Update existing record
    UPDATE public.hr_emploc
       SET hr_status   = COALESCE(hr_status, 'Pending'),
           updated_at  = NOW()
     WHERE id = v_hr.id
    RETURNING * INTO v_hr;
  ELSE
    -- Insert new HR Emploc (stationary path)
    IF NOT v_is_roving THEN
      INSERT INTO public.hr_emploc (
        employee_name, full_name, applicant_id,
        vcode, vacancy_id, vacancy_code_snapshot,
        account, account_id, chain_id, store_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        store_name, hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.id, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.store_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.store_name, v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Stationary'::public.hr_emploc_assignment_type,
        NULL, '[]'::jsonb
      )
      RETURNING * INTO v_hr;
    END IF;
  END IF;

  -- ── Audit log ────────────────────────────────────────────────────────────
  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    COALESCE(v_hr.emploc_no, v_app.full_name),
    v_vac.vcode,
    'confirmed_onboard',
    'Applicant confirmed onboard and moved to HR Emploc for ' || v_vac.vcode,
    v_actor_name,
    jsonb_build_object(
      'applicant_id',               v_app.id,
      'hr_emploc_id',               v_hr.id,
      'vacancy_id',                 v_vac.id,
      'role',                       v_role,
      'hired_by_user_id',           v_hired_by_id,
      'endorsed_by_deployer_id',    p_endorsed_by_deployer_id,
      'endorsed_by_name',           p_endorsed_by_name,
      'is_roving',                  v_is_roving,
      'hired_date',                 v_app.hired_date,
      'late_store_linked',          v_late_result IS NOT NULL,
      'vacancy_requirement_id',     p_vacancy_requirement_id,
      'movement_at',                NOW()
    )
  );

  -- ── §1A: Increment hc_filled on the selected requirement ────────────────
  -- ohm#91c5af4e — HC Sync: atomically increment hc_filled.
  -- The trg_check_vr_capacity trigger will raise if hc_filled would exceed
  -- hc_needed (defense-in-depth; we also guard here for clear error message).
  IF p_vacancy_requirement_id IS NOT NULL THEN
    UPDATE public.vacancy_requirements
       SET hc_filled = hc_filled + 1
     WHERE id = p_vacancy_requirement_id
       AND hc_filled < hc_needed;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'requirement_already_full'
        USING MESSAGE = 'The selected position requirement has no remaining headcount. '
                        'Another hire may have filled it concurrently.',
              HINT    = 'Refresh the vacancy and select a different requirement.';
    END IF;

  ELSE
    -- §1B: Backward-compat fallback — auto-fill the first available requirement
    -- for this vacancy (silent no-op when no vacancy_requirements rows exist).
    UPDATE public.vacancy_requirements
       SET hc_filled = hc_filled + 1
     WHERE id = (
       SELECT id
         FROM public.vacancy_requirements
        WHERE vacancy_id = v_vac.id
          AND hc_filled < hc_needed
        ORDER BY created_at
        LIMIT 1
     )
       AND hc_filled < hc_needed;
    -- NOT FOUND here: fine — legacy vacancies with no requirements rows.
  END IF;

  -- ── Phase 6.2: non-blocking slot pipeline→hr_processing sync ─────────────
  IF NOT v_is_roving THEN
    PERFORM public.fn_sync_slot_to_hr_processing(
      p_vcode        => v_vac.vcode,
      p_applicant_id => v_app.id,
      p_performed_by => v_profile_id,
      p_source_fn    => 'confirm_applicant_onboard'
    );
  END IF;

  RETURN jsonb_build_object(
    'ok',                       true,
    'applicant_id',             v_app.id,
    'applicant_status',         v_app.status,
    'hr_emploc_id',             v_hr.id,
    'vcode',                    v_vac.vcode,
    'hired_by_user_id',         v_hired_by_id,
    'hired_date',               v_app.hired_date,
    'is_roving',                v_is_roving,
    'late_store_linked',        v_late_result,
    'vacancy_requirement_id',   p_vacancy_requirement_id
  );
END;
$function$;

COMMENT ON FUNCTION public.confirm_applicant_onboard(uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date, uuid) IS
  'ohm#3bd81e6a / ohm#91c5af4e — Extends 20260813000002 with p_vacancy_requirement_id (uuid DEFAULT NULL). '
  'When supplied, atomically increments vacancy_requirements.hc_filled (raises requirement_already_full if full). '
  'When NULL, backward-compat fallback auto-selects first available requirement for the vacancy (silent no-op when none). '
  'Phase 6.2 (OHM2026_0020): slot pipeline→hr_processing sync on stationary non-fast-track path. '
  'hc_filled increment placed AFTER audit log write, BEFORE Phase 6.2 hook.';

-- Grant EXECUTE to authenticated (same as prior overload)
GRANT EXECUTE ON FUNCTION public.confirm_applicant_onboard(
  uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date, uuid
) TO authenticated;


-- ============================================================
-- §2  Patch fn_plantilla_separation_to_vacancy — hc_filled decrement
-- ============================================================
--
-- ohm#91c5af4e: When a stationary employee resigns/is separated, decrement
-- hc_filled on their vacancy's most-filled requirement that still has hc_filled > 0.
--
-- Design note: We cannot resolve the exact vacancy_requirement_id used at
-- confirm_applicant_onboard time because plantilla rows do not carry that FK yet
-- (deferred per ADR-001 RPC-first rule). For the current 1-requirement-per-vacancy
-- backfill, the first-found decrement is safe. Multi-requirement support requires
-- adding vacancy_requirement_id to the plantilla table in a future migration.
--
-- Source base: 20260916000000_fix_fractional_hc_vacancy_and_inactive_esa_cleanup.sql
-- The ONLY addition is the UPDATE block labelled §2A below; the rest of the function
-- body is reproduced byte-for-byte from that migration.

CREATE OR REPLACE FUNCTION public.fn_plantilla_separation_to_vacancy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_link        RECORD;
  v_vac         public.vacancies%ROWTYPE;
  v_esa         RECORD;
  v_new_link_id uuid;
  v_hc          numeric;
BEGIN
  -- Guard: only fire on relevant status transitions.
  IF OLD.status NOT IN ('Active', 'On Leave', 'For Deactivation')
    OR NEW.status NOT IN ('Resigned', 'AWOL', 'Endo', 'Terminated', 'Others',
                          'Inactive', 'Floating', 'For Deactivation')
    OR OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- ── Roving employee path ─────────────────────────────────────────────────
  IF COALESCE(NEW.is_roving, false) THEN

    -- Path A: process via plantilla_store_links
    IF EXISTS (
      SELECT 1 FROM public.plantilla_store_links
       WHERE plantilla_id = NEW.id AND is_active = true
    ) THEN
      FOR v_link IN
        SELECT * FROM public.plantilla_store_links
         WHERE plantilla_id = NEW.id AND is_active = true
      LOOP
        -- Determine the HC for this store from ESA filled_hc
        SELECT COALESCE(esa.filled_hc, 1)::numeric INTO v_hc
          FROM public.employee_store_allocations esa
         WHERE esa.plantilla_id        = NEW.id
           AND esa.store_id            = v_link.store_id
           AND esa.is_active           = true
         LIMIT 1;

        v_hc := COALESCE(v_hc, 1);

        -- Fetch the vacancy for this store link
        IF v_link.vacancy_id IS NOT NULL THEN
          SELECT * INTO v_vac FROM public.vacancies
           WHERE id = v_link.vacancy_id AND deleted_at IS NULL LIMIT 1;
        ELSE
          SELECT * INTO v_vac FROM public.vacancies
           WHERE vcode = v_link.vcode AND deleted_at IS NULL LIMIT 1;
        END IF;

        IF v_vac.id IS NOT NULL THEN
          -- Reopen or create the vacancy
          IF v_vac.status IN ('Filled', 'Closed') THEN
            UPDATE public.vacancies
               SET status         = 'Open',
                   is_archived    = false,
                   archived_at    = NULL,
                   archived_by    = NULL,
                   required_headcount = GREATEST(
                                         COALESCE(required_headcount, 0) + v_hc,
                                         1
                                       ),
                   updated_at     = NOW()
             WHERE id = v_vac.id;
          ELSE
            UPDATE public.vacancies
               SET required_headcount = GREATEST(
                                         COALESCE(required_headcount, 0) + v_hc,
                                         1
                                       ),
                   updated_at = NOW()
             WHERE id = v_vac.id;
          END IF;
        END IF;

        -- Deactivate the store link
        UPDATE public.plantilla_store_links
           SET is_active   = false,
               deactivated_at = NOW()
         WHERE id = v_link.id;

      END LOOP;  -- end Path A loop

    ELSE
      -- Path B: no store links — fall back to employee_store_allocations
      FOR v_esa IN
        SELECT * FROM public.employee_store_allocations
         WHERE plantilla_id = NEW.id AND is_active = true
      LOOP
        v_hc := COALESCE(v_esa.filled_hc, 1)::numeric;

        -- Fetch the vacancy for this store
        SELECT * INTO v_vac FROM public.vacancies
         WHERE store_id    = v_esa.store_id
           AND account_id  = NEW.account_id
           AND is_roving   = true
           AND deleted_at  IS NULL
           AND status NOT IN ('Filled', 'Closed', 'Cancelled')
         LIMIT 1;

        IF NOT FOUND THEN
          -- Create a new roving vacancy
          INSERT INTO public.vacancies (
            vcode, account, account_id, store_id, position, position_id,
            status, vacancy_type, is_roving, required_headcount,
            source, created_at, updated_at
          )
          SELECT
            v_esa.store_id::text,  -- placeholder; real VCODE via fn
            NEW.account,
            NEW.account_id,
            v_esa.store_id,
            NEW.position,
            NEW.position_id,
            'Open',
            'Backfill',
            true,
            GREATEST(v_hc, 1),
            'plantilla',
            NOW(),
            NOW()
          RETURNING * INTO v_vac;
        ELSE
          UPDATE public.vacancies
             SET required_headcount = GREATEST(
                                       COALESCE(required_headcount, 0) + v_hc,
                                       1
                                     ),
                 status    = CASE
                               WHEN status IN ('Filled', 'Closed') THEN 'Open'
                               ELSE status
                             END,
                 is_archived = false,
                 archived_at = NULL,
                 archived_by = NULL,
                 updated_at  = NOW()
           WHERE id = v_vac.id
          RETURNING * INTO v_vac;
        END IF;

        -- Reconcile store link
        INSERT INTO public.plantilla_store_links (
          plantilla_id, store_id, vcode, vacancy_id, is_active
        )
        SELECT NEW.id, v_esa.store_id,
               COALESCE(v_vac.vcode, v_esa.store_id::text),
               v_vac.id, false
         WHERE NOT EXISTS (
           SELECT 1 FROM public.plantilla_store_links psl
            WHERE psl.plantilla_id = NEW.id
              AND psl.store_id     = v_esa.store_id
         )
        RETURNING id INTO v_new_link_id;

        IF v_new_link_id IS NOT NULL THEN
          UPDATE public.plantilla_store_links
             SET deactivated_at = NOW()
           WHERE id = (
             SELECT id FROM public.plantilla_store_links
              WHERE plantilla_id = NEW.id
                AND store_id     = v_esa.store_id
              ORDER BY created_at DESC
              LIMIT 1
           );
        END IF;
      END LOOP;  -- end Path B loop
    END IF;

    -- ── Deactivate ESA rows for this roving employee after vacancy handling ─
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

  -- §2A: ohm#91c5af4e — Decrement hc_filled on the reopened vacancy's requirement.
  -- Targets the most-filled (but not empty) requirement for the employee's vacancy.
  -- Safe for the current 1-requirement-per-vacancy backfill; multi-requirement
  -- FK linkage deferred (requires vacancy_requirement_id on plantilla table).
  UPDATE public.vacancy_requirements
     SET hc_filled = GREATEST(0, hc_filled - 1)
   WHERE id = (
     SELECT vr.id
       FROM public.vacancy_requirements vr
       JOIN public.vacancies v
         ON v.id = vr.vacancy_id
      WHERE v.store_id   = NEW.store_id
        AND v.account_id = NEW.account_id
        AND vr.hc_filled > 0
        AND v.deleted_at IS NULL
      ORDER BY vr.hc_filled DESC
      LIMIT 1
   );
  -- NOT FOUND: silent — legacy vacancies with no requirement rows; or store_id NULL.

  -- Deactivate ESA rows for stationary employees.
  UPDATE public.employee_store_allocations
     SET is_active     = false,
         effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
   WHERE plantilla_id = NEW.id
     AND is_active    = true;

  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.fn_plantilla_separation_to_vacancy() IS
  'ohm#91c5af4e — Extends 20260916000000 with §2A: hc_filled decrement on vacancy_requirements '
  'for stationary separations. Targets the most-filled requirement for the employee''s store+account vacancy. '
  'Silent no-op for legacy vacancies with no requirement rows. '
  'Roving path and all other behavior unchanged from 20260916000000.';


-- ============================================================
-- §3  Verification queries (run manually after applying)
-- ============================================================
--
-- V1 — New param exists on function
--   SELECT COUNT(*) FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public'
--     AND p.proname = 'confirm_applicant_onboard'
--     AND array_length(p.proargtypes, 1) = 13;
--   -- Expected: 1
--
-- V2 — hc_filled increment (roll back after)
--   BEGIN;
--     -- (manually call confirm_applicant_onboard with a real applicant_id and valid
--     --  p_vacancy_requirement_id to verify hc_filled increments by 1)
--     SELECT id, hc_filled, hc_needed FROM vacancy_requirements WHERE id = '<req_id>';
--   ROLLBACK;
--
-- V3 — requirement_already_full error fires (roll back after)
--   BEGIN;
--     UPDATE vacancy_requirements SET hc_filled = hc_needed WHERE id = '<req_id>';
--     -- then call confirm_applicant_onboard with that req_id → expect SQLSTATE P0001
--     --   MESSAGE: 'requirement_already_full'
--   ROLLBACK;
--
-- V4 — fallback NULL path no-ops for vacancy with no requirements
--   SELECT COUNT(*) FROM vacancy_requirements WHERE vacancy_id = '<legacy_vacancy_id>';
--   -- Expected: 0 → confirm_applicant_onboard with NULL req_id should still succeed
--
-- V5 — separation trigger decrement
--   BEGIN;
--     -- Simulate resign: UPDATE plantilla SET status='Resigned' WHERE id='<id>'
--     -- Then: SELECT hc_filled FROM vacancy_requirements WHERE vacancy_id = '<vac_id>';
--     -- Expected: hc_filled decreased by 1 (or unchanged if was already 0)
--   ROLLBACK;
