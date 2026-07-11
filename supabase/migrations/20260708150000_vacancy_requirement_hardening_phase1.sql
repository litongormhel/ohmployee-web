-- Migration: 20260708150000_vacancy_requirement_hardening_phase1
-- Prompt ID: ohm#c7a9f2d1 (Phase 1 Hardening — reduced scope, see note below)
--
-- SCOPE NOTE (deviation from original prompt, approved by Ohm):
--   The original prompt required `plantilla.vacancy_requirement_id` to be NOT NULL
--   after a best-effort backfill. Verified live on staging before writing this
--   migration: only 19/376 active plantilla rows have `vacancy_id` populated at
--   all (most plantilla rows link to vacancies via the `vcode` text column, not
--   the `vacancy_id` FK — pool hires, Coverage/roving hires, and the vast
--   majority of stationary hires never populate it), and the prompt's own
--   backfill join (`vr.vacancy_id = p.vacancy_id AND vr.hc_filled > 0`) matches
--   ZERO active plantilla rows on this database. Forcing NOT NULL would either
--   fail outright (existing NULL violates it) or, if forced, permanently block
--   every future plantilla INSERT for pool/roving/most-stationary hires — the
--   opposite of "ZERO regressions". Ohm approved: ship the FK as NULLABLE,
--   populate it deterministically going forward wherever the requirement is
--   known, and keep the existing "most-filled requirement" heuristic as the
--   fallback ONLY for rows where the FK is absent (legacy path, unchanged
--   behavior). This preserves ADR-001 (pool/roving are not vacancy_requirements
--   participants) while making the common stationary case deterministic.
--
-- Depends on:
--   20260708012728_add_vacancy_requirements_normalization.sql (vacancy_requirements table)
--   20260708140000_assignment_hc_sync.sql (confirm_applicant_onboard 13-arg signature,
--     fn_plantilla_separation_to_vacancy heuristic decrement)
--
-- Validation queries at bottom of file.

-- ============================================================
-- TASK 1 — Resolve NULL position_id on ACTIVE, non-archived vacancies
-- ============================================================
-- Scoped to active/non-archived only (matches the prior normalization
-- migration's explicit decision to leave the 127 historical/archived gaps
-- untouched). Live-verified: exactly 1 row affected (VCSSG2_0300).

INSERT INTO public.positions (position_name, created_at)
SELECT 'Unspecified', now()
WHERE NOT EXISTS (
  SELECT 1 FROM public.positions WHERE position_name = 'Unspecified'
);

INSERT INTO public.vacancy_requirements (
  vacancy_id, position_id, employment_type, hc_needed, hc_filled, created_at
)
SELECT
  v.id,
  p.id,
  v.employment_type,
  GREATEST(COALESCE(v.required_headcount, 1), 1),
  0,
  now()
FROM public.vacancies v
CROSS JOIN public.positions p
WHERE p.position_name = 'Unspecified'
  AND v.position_id IS NULL
  AND v.deleted_at IS NULL
  AND COALESCE(v.is_archived, false) = false
  AND NOT EXISTS (
    SELECT 1 FROM public.vacancy_requirements vr WHERE vr.vacancy_id = v.id
  );

-- ============================================================
-- TASK 2 (reduced) — Nullable vacancy_requirement_id linkage
-- ============================================================

ALTER TABLE public.hr_emploc
  ADD COLUMN IF NOT EXISTS vacancy_requirement_id uuid;

ALTER TABLE public.hr_emploc
  DROP CONSTRAINT IF EXISTS fk_hr_emploc_vacancy_requirement;

ALTER TABLE public.hr_emploc
  ADD CONSTRAINT fk_hr_emploc_vacancy_requirement
  FOREIGN KEY (vacancy_requirement_id)
  REFERENCES public.vacancy_requirements(id)
  ON DELETE SET NULL;

ALTER TABLE public.plantilla
  ADD COLUMN IF NOT EXISTS vacancy_requirement_id uuid;

ALTER TABLE public.plantilla
  DROP CONSTRAINT IF EXISTS fk_plantilla_vacancy_requirement;

ALTER TABLE public.plantilla
  ADD CONSTRAINT fk_plantilla_vacancy_requirement
  FOREIGN KEY (vacancy_requirement_id)
  REFERENCES public.vacancy_requirements(id)
  ON DELETE SET NULL;

-- No backfill UPDATE — the prompt's proposed join matches 0 rows on live data
-- (see scope note above). Both columns start NULL for all existing rows and
-- are populated only going forward via §3/§4 below.

-- ============================================================
-- TASK 5 — Trigger hardening (explicit negative guard)
-- ============================================================
-- hc_filled >= 0 and hc_needed > 0 are already enforced by CHECK constraints
-- (vacancy_requirements_hc_filled_check / _hc_needed_check, confirmed live).
-- Adding an explicit trigger-level guard for a clearer application error
-- message, in addition to the constraint (defense-in-depth, no behavior change
-- for any value that already passed the constraint).

CREATE OR REPLACE FUNCTION public.check_vr_capacity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.hc_filled > new.hc_needed then
    raise exception 'HC exceeded for requirement %: hc_filled (%) > hc_needed (%)',
      new.id, new.hc_filled, new.hc_needed;
  end if;
  if new.hc_filled < 0 then
    raise exception 'HC cannot be negative for requirement %: hc_filled (%)',
      new.id, new.hc_filled;
  end if;
  return new;
end;
$function$;

-- ============================================================
-- §3  Patch confirm_applicant_onboard — persist vacancy_requirement_id on hr_emploc
-- ============================================================
-- Same 13-arg signature as 20260708140000 (CREATE OR REPLACE, no DROP needed).
-- Only addition: the hr_emploc INSERT/UPDATE now carries p_vacancy_requirement_id
-- through to the new hr_emploc.vacancy_requirement_id column so move_to_plantilla
-- (§4 below) can later carry it forward onto the plantilla row deterministically.
-- All other logic reproduced byte-for-byte from 20260708140000.

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
  v_existing_plt      public.plantilla%ROWTYPE;
  v_roving_id         uuid;
  v_new_roving        boolean := false;
  v_plt_store_link_id uuid;
  v_existing_employee_no text;
  v_roving_hr_found   boolean := false;
BEGIN
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Data Team, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

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

  IF p_hired_by_user_id IS NOT NULL THEN
    v_hired_by_id := p_hired_by_user_id;
  ELSE
    v_hired_by_id := public.get_my_auth_uid();
  END IF;

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

  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id;

  IF v_is_roving AND p_roving_assignment_id IS NULL THEN
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
    v_late_result := public.link_late_store_to_plantilla(
      p_plantilla_id      => v_existing_plt.id,
      p_vcode             => v_vac.vcode,
      p_vacancy_id        => v_vac.id,
      p_applicant_id      => v_app.id,
      p_performed_by      => v_profile_id
    );
  END IF;

  SELECT * INTO v_hr
    FROM public.hr_emploc
   WHERE applicant_id = p_applicant_id
   LIMIT 1;

  IF v_hr.id IS NOT NULL THEN
    UPDATE public.hr_emploc
       SET hr_status              = COALESCE(hr_status, 'Pending'),
           vacancy_requirement_id = COALESCE(vacancy_requirement_id, p_vacancy_requirement_id),
           updated_at             = NOW()
     WHERE id = v_hr.id
    RETURNING * INTO v_hr;
  ELSE
    IF NOT v_is_roving THEN
      INSERT INTO public.hr_emploc (
        employee_name, full_name, applicant_id,
        vcode, vacancy_id, vacancy_code_snapshot,
        account, account_id, chain_id, store_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        store_name, hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores,
        vacancy_requirement_id
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.id, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.store_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.store_name, v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Stationary'::public.hr_emploc_assignment_type,
        NULL, '[]'::jsonb,
        p_vacancy_requirement_id
      )
      RETURNING * INTO v_hr;
    END IF;
  END IF;

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
  END IF;

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
  'ohm#c7a9f2d1 — Extends 20260708140000: hr_emploc.vacancy_requirement_id is now persisted '
  '(INSERT + UPDATE-existing path) so move_to_plantilla can carry it forward deterministically. '
  'All other logic byte-identical to 20260708140000.';

-- ============================================================
-- §4  Patch move_to_plantilla — carry vacancy_requirement_id onto plantilla
-- ============================================================
-- Adds the vacancy_requirement_id column to all 4 plantilla INSERT branches,
-- sourced from v_emp.vacancy_requirement_id (NULL unless set by
-- confirm_applicant_onboard's stationary non-fast-track path above — pool,
-- roving, and CGCODE-coverage hr_emploc rows never populate it, matching
-- ADR-001: those paths are not vacancy_requirements participants). All other
-- logic reproduced byte-for-byte from the live function body.

CREATE OR REPLACE FUNCTION public.move_to_plantilla(p_id uuid)
RETURNS plantilla
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
/*
  OHM2026_0081: for the pure-stationary path, fn_sync_slot_to_occupied is now
  called BEFORE the vacancy status updates, and both vacancy-closing UPDATEs
  carry a NOT EXISTS slot guard.  Only when all non-closed slots are occupied
  (no open/pipeline/hr_processing remaining) does the vacancy transition to
  'Filled' — preventing premature archival on the first hire of a multi-slot
  vacancy.

  ohm#f4k2x9m8q: CGCODE coverage sub-path now populates plantilla_store_links
  from confirmed hr_emploc_store_links (mirroring the Roving branch) and syncs
  employee_store_allocations, closing the gap where Coverage hires produced an
  employee with zero store assignments. All 4 branches now also carry
  contact_no forward from hr_emploc.contact_number_snapshot. No HC Share logic
  touched (ADR-001).

  ohm#c7a9f2d1: all 4 branches now also carry vacancy_requirement_id forward
  from hr_emploc.vacancy_requirement_id (NULL for pool/roving/coverage, set
  only for stationary hires that went through the requirement-selection flow).
*/
DECLARE
  v_emp             public.hr_emploc;
  v_pl              public.plantilla;
  v_actor           uuid := get_my_profile_id();
  v_is_pool         boolean := false;
  v_pool_type_id    uuid;
  v_home_account_id uuid;
  v_home_acct       public.accounts;
BEGIN
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

  IF EXISTS (
    SELECT 1
      FROM public.plantilla
     WHERE hr_emploc_id              = p_id
       AND COALESCE(is_deleted, false) = false
  ) THEN
    RAISE EXCEPTION 'hr_emploc % already moved to plantilla', p_id USING ERRCODE = '23505';
  END IF;

  IF v_emp.moved_to_plantilla_at IS NOT NULL THEN
    RAISE EXCEPTION
      'hr_emploc % already has moved_to_plantilla_at set', p_id USING ERRCODE = '23505';
  END IF;

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
      contact_no,
      vacancy_requirement_id,
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
      v_emp.contact_number_snapshot,
      v_emp.vacancy_requirement_id,
      v_actor, v_actor, v_actor,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE id = v_emp.vacancy_id;
    END IF;

    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL;

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
      contact_no,
      vacancy_requirement_id,
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
      v_emp.contact_number_snapshot,
      v_emp.vacancy_requirement_id,
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

    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL;

  -- ── STATIONARY PATH / CGCODE COVERAGE SUB-PATH ─────────────────────────────
  ELSE

    IF v_emp.coverage_slot_id IS NOT NULL THEN
      -- ── CGCODE COVERAGE SUB-PATH ──────────────────────────────────────────
      INSERT INTO plantilla (
        account,              account_id,           chain_id,             province_id,
        position,             position_id,
        employee_no,          emploc_no,
        employee_name,        employee_name_snapshot,
        civil_status,         date_of_birth,
        sss_no,               philhealth_no,         pagibig_no,
        date_hired,           vacancy_id,            vacancy_code_snapshot,
        vcode,
        hrco_name,            hrco_user_id_snapshot,
        om_user_id_snapshot,  atl_user_id_snapshot,
        area,                 area_name_snapshot,
        hr_emploc_id,
        coverage_slot_id,     coverage_group_id,
        deployment_type,
        status,               tagged_at,
        contact_no,
        vacancy_requirement_id,
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
        v_emp.hired_date, v_emp.vacancy_id, v_emp.vacancy_code_snapshot,
        v_emp.vcode,
        v_emp.hrco_name, v_emp.hrco_user_id_snapshot,
        v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
        v_emp.area_name_snapshot, v_emp.area_name_snapshot,
        v_emp.id,
        v_emp.coverage_slot_id, v_emp.coverage_group_id,
        'Roving',
        'Active', CURRENT_DATE,
        v_emp.contact_number_snapshot,
        v_emp.vacancy_requirement_id,
        v_actor, v_actor, v_actor,
        NOW(), NOW()
      )
      RETURNING * INTO v_pl;

      INSERT INTO public.plantilla_store_links (
        plantilla_id,
        hr_emploc_store_link_id,
        coverage_group_id,
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
        sl.id,
        sl.coverage_group_id,
        s.vcode,
        sl.store_name,
        sl.account,
        'Active',
        NOW(),
        v_actor,
        v_actor,
        v_actor
      FROM public.hr_emploc_store_links sl
      JOIN public.stores s ON s.id = sl.store_id
      WHERE sl.hr_emploc_id = p_id
        AND sl.status       = 'Confirmed'
        AND sl.deleted_at   IS NULL;

      PERFORM public.fn_sync_employee_store_allocations(v_pl.employee_no);

      IF v_emp.vacancy_id IS NOT NULL THEN
        UPDATE vacancies
           SET status     = 'Filled',
               updated_at = NOW(),
               updated_by = v_actor
         WHERE id = v_emp.vacancy_id;
      END IF;

      UPDATE public.vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE vcode      = v_emp.vcode
         AND status     IN ('Open', 'For Sourcing')
         AND COALESCE(is_archived, false) = false
         AND deleted_at IS NULL;

    ELSE
      -- ── PURE STATIONARY PATH ──────────────────────────────────────────────
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
        contact_no,
        vacancy_requirement_id,
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
        v_emp.contact_number_snapshot,
        v_emp.vacancy_requirement_id,
        v_actor, v_actor, v_actor, NOW(), NOW()
      )
      RETURNING * INTO v_pl;

      PERFORM public.fn_sync_slot_to_occupied(
        p_vcode        => v_emp.vcode,
        p_hr_emploc_id => p_id,
        p_plantilla_id => v_pl.id,
        p_performed_by => v_actor,
        p_source_fn    => 'move_to_plantilla'
      );

      IF v_emp.vacancy_id IS NOT NULL THEN
        UPDATE vacancies
           SET status     = 'Filled',
               updated_at = NOW(),
               updated_by = v_actor
         WHERE id = v_emp.vacancy_id
           AND NOT EXISTS (
             SELECT 1 FROM public.plantilla_slots ps
             WHERE ps.legacy_vcode = v_emp.vcode
               AND ps.is_roving    = false
               AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
           );
      END IF;

      UPDATE public.vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE vcode      = v_emp.vcode
         AND status     IN ('Open', 'For Sourcing')
         AND COALESCE(is_archived, false) = false
         AND deleted_at IS NULL
         AND NOT EXISTS (
           SELECT 1 FROM public.plantilla_slots ps
           WHERE ps.legacy_vcode = v_emp.vcode
             AND ps.is_roving    = false
             AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
         );

    END IF;

  END IF;

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

  IF v_emp.coverage_slot_id IS NOT NULL THEN
    PERFORM public.fn_sync_coverage_slot_to_active(
      p_coverage_slot_id => v_emp.coverage_slot_id,
      p_plantilla_id     => v_pl.id,
      p_performed_by     => v_actor,
      p_source_fn        => 'move_to_plantilla'
    );
  END IF;

  RETURN v_pl;
END
$function$;

COMMENT ON FUNCTION public.move_to_plantilla(uuid) IS
  'ohm#c7a9f2d1 — Extends the live function: all 4 branches now carry '
  'hr_emploc.vacancy_requirement_id forward onto plantilla.vacancy_requirement_id '
  '(NULL for pool/roving/coverage — unchanged ADR-001 scope). All other logic '
  'byte-identical to the pre-existing live body.';

-- ============================================================
-- §5  Patch fn_plantilla_separation_to_vacancy — deterministic decrement when linked
-- ============================================================
-- Stationary path only (roving path above is untouched). When the separating
-- plantilla row carries vacancy_requirement_id (set by §3/§4 above for hires
-- made after this migration), decrement that exact row. Otherwise, fall back
-- to the pre-existing "most-filled requirement" heuristic — unchanged behavior
-- for every plantilla row hired before this migration.

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
  IF OLD.status NOT IN ('Active', 'On Leave', 'For Deactivation')
    OR NEW.status NOT IN ('Resigned', 'AWOL', 'Endo', 'Terminated', 'Others',
                          'Inactive', 'Floating', 'For Deactivation')
    OR OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- ── Roving employee path ─────────────────────────────────────────────────
  IF COALESCE(NEW.is_roving, false) THEN

    IF EXISTS (
      SELECT 1 FROM public.plantilla_store_links
       WHERE plantilla_id = NEW.id AND is_active = true
    ) THEN
      FOR v_link IN
        SELECT * FROM public.plantilla_store_links
         WHERE plantilla_id = NEW.id AND is_active = true
      LOOP
        SELECT COALESCE(esa.filled_hc, 1)::numeric INTO v_hc
          FROM public.employee_store_allocations esa
         WHERE esa.plantilla_id        = NEW.id
           AND esa.store_id            = v_link.store_id
           AND esa.is_active           = true
         LIMIT 1;

        v_hc := COALESCE(v_hc, 1);

        IF v_link.vacancy_id IS NOT NULL THEN
          SELECT * INTO v_vac FROM public.vacancies
           WHERE id = v_link.vacancy_id AND deleted_at IS NULL LIMIT 1;
        ELSE
          SELECT * INTO v_vac FROM public.vacancies
           WHERE vcode = v_link.vcode AND deleted_at IS NULL LIMIT 1;
        END IF;

        IF v_vac.id IS NOT NULL THEN
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

        UPDATE public.plantilla_store_links
           SET is_active   = false,
               deactivated_at = NOW()
         WHERE id = v_link.id;

      END LOOP;

    ELSE
      FOR v_esa IN
        SELECT * FROM public.employee_store_allocations
         WHERE plantilla_id = NEW.id AND is_active = true
      LOOP
        v_hc := COALESCE(v_esa.filled_hc, 1)::numeric;

        SELECT * INTO v_vac FROM public.vacancies
         WHERE store_id    = v_esa.store_id
           AND account_id  = NEW.account_id
           AND is_roving   = true
           AND deleted_at  IS NULL
           AND status NOT IN ('Filled', 'Closed', 'Cancelled')
         LIMIT 1;

        IF NOT FOUND THEN
          INSERT INTO public.vacancies (
            vcode, account, account_id, store_id, position, position_id,
            status, vacancy_type, is_roving, required_headcount,
            source, created_at, updated_at
          )
          SELECT
            v_esa.store_id::text,
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
      END LOOP;
    END IF;

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

  -- §5A: ohm#c7a9f2d1 — deterministic decrement when the FK is known.
  IF NEW.vacancy_requirement_id IS NOT NULL THEN
    UPDATE public.vacancy_requirements
       SET hc_filled = GREATEST(0, hc_filled - 1)
     WHERE id = NEW.vacancy_requirement_id;
  ELSE
    -- §5B: ohm#91c5af4e heuristic fallback — unchanged for rows hired before
    -- this migration (vacancy_requirement_id never populated on the FK).
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
  END IF;

  UPDATE public.employee_store_allocations
     SET is_active     = false,
         effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
   WHERE plantilla_id = NEW.id
     AND is_active    = true;

  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.fn_plantilla_separation_to_vacancy() IS
  'ohm#c7a9f2d1 — Extends 20260708140000''s §2A: when NEW.vacancy_requirement_id '
  'is set, decrements that exact row (deterministic). Otherwise falls back to the '
  'pre-existing most-filled-requirement heuristic, unchanged for legacy hires. '
  'Roving path and all other behavior unchanged.';

-- ============================================================
-- TASK 4 — Reconciliation view (deterministic subset only)
-- ============================================================
-- Keyed off plantilla.vacancy_requirement_id — the only deterministic link
-- that exists. Rows hired before this migration (or via pool/roving/coverage,
-- which never populate this FK) are outside this view's reconciliation scope
-- by design; they are still governed by the unchanged heuristic in §5B above.

CREATE OR REPLACE VIEW public.vw_requirement_reconciliation AS
SELECT
  vr.id,
  vr.vacancy_id,
  vr.hc_needed,
  vr.hc_filled,
  COUNT(p.id) FILTER (
    WHERE p.status IN ('Active', 'On Leave', 'For Deactivation')
      AND COALESCE(p.is_deleted, false) = false
  ) AS actual_filled_linked,
  vr.hc_filled - COUNT(p.id) FILTER (
    WHERE p.status IN ('Active', 'On Leave', 'For Deactivation')
      AND COALESCE(p.is_deleted, false) = false
  ) AS delta
FROM public.vacancy_requirements vr
LEFT JOIN public.plantilla p ON p.vacancy_requirement_id = vr.id
GROUP BY vr.id;

GRANT SELECT ON public.vw_requirement_reconciliation TO authenticated;

-- ============================================================
-- §6  Validation queries (run manually after applying)
-- ============================================================
--
-- V1 — Task 1 invariant, scoped to active/non-archived vacancies only
--   SELECT v.id FROM public.vacancies v
--   LEFT JOIN public.vacancy_requirements vr ON vr.vacancy_id = v.id
--   WHERE v.deleted_at IS NULL AND COALESCE(v.is_archived, false) = false
--   GROUP BY v.id HAVING COUNT(vr.id) = 0;
--   -- Expected: 0 rows (127 historical/archived gaps remain, out of scope by design)
--
-- V2 — new columns exist
--   SELECT column_name FROM information_schema.columns
--   WHERE table_name IN ('hr_emploc','plantilla') AND column_name = 'vacancy_requirement_id';
--   -- Expected: 2 rows
--
-- V3 — reconciliation view has no drift among linked requirements (only
--       meaningful once hires start flowing through the new FK path)
--   SELECT * FROM public.vw_requirement_reconciliation WHERE delta != 0;
--
-- V4 — trigger negative guard (roll back after)
--   BEGIN;
--     UPDATE vacancy_requirements SET hc_filled = -1 WHERE id = '<req_id>';
--     -- expect exception
--   ROLLBACK;
