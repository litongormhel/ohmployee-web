-- Migration: 20261027160000_fix_vacancy_transition_on_move_to_plantilla.sql
-- Description:
--   Ensures that when an employee completes onboarding and moves to Plantilla
--   (via move_to_plantilla or approve_plantilla_import_batch), any associated
--   vacancies in 'Pipeline', 'For Sourcing', or 'Open' status correctly transition
--   to 'Filled', preventing orphan vacancy slots from lingering in Vacancy queries.

BEGIN;

-- ============================================================================
-- Section 1. Update move_to_plantilla with comprehensive vacancy status predicates
-- ============================================================================

CREATE OR REPLACE FUNCTION public.move_to_plantilla(p_id uuid)
RETURNS public.plantilla
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
/*
  OHM2026_0081 + ohm#plan07:
  Ensures vacancy status transition to 'Filled' captures requisitions in 'Pipeline',
  'For Sourcing', and 'Open' status once all slots are occupied.
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
     WHERE hr_emploc_id              = p_id
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

    -- Close via vacancy_id if available (pool vacancy semantics: single-slot)
    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE id = v_emp.vacancy_id;
    END IF;

    -- VCODE fallback: close any remaining Open/Pipeline vacancy for this VCODE
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing', 'Pipeline')
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

    -- VCODE fallback: close any remaining Open/Pipeline vacancy for the roving VCODE
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing', 'Pipeline')
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
        v_actor, v_actor, v_actor,
        NOW(), NOW()
      )
      RETURNING * INTO v_pl;

      -- Close carrier CGCODE vacancy via vacancy_id if available
      IF v_emp.vacancy_id IS NOT NULL THEN
        UPDATE vacancies
           SET status     = 'Filled',
               updated_at = NOW(),
               updated_by = v_actor
         WHERE id = v_emp.vacancy_id;
      END IF;

      -- VCODE fallback: close any remaining Open/Pipeline carrier vacancy
      UPDATE public.vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE vcode      = v_emp.vcode
         AND status     IN ('Open', 'For Sourcing', 'Pipeline')
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

      PERFORM public.fn_sync_slot_to_occupied(
        p_vcode        => v_emp.vcode,
        p_hr_emploc_id => p_id,
        p_plantilla_id => v_pl.id,
        p_performed_by => v_actor,
        p_source_fn    => 'move_to_plantilla'
      );

      -- Close via vacancy_id only when all non-closed slots are occupied
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

      -- VCODE fallback: close vacancy when truly every slot is occupied
      UPDATE public.vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE vcode      = v_emp.vcode
         AND status     IN ('Open', 'For Sourcing', 'Pipeline')
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
END;
$function$;

COMMIT;
