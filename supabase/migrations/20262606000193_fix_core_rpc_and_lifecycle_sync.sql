-- ============================================================================
-- Migration: 20262606000193_fix_core_rpc_and_lifecycle_sync.sql
-- Module: Core RPC & Lifecycle Synchronization (Smoke Test Phase 3)
-- Work items:
--   - Bug 3: Contact Number inheritance from HR Emploc / Applicant to Plantilla
--   - Bug 4: Blank Employment Type fix (defaults and derived values in Plantilla)
--   - Bug 8: Resignation Vacancy Date & Ownership Attribution (VAC-MNL-099)
--   - Bug 21: Preserving custom requested position on approval / slot creation
--   - Bug 25: Existing store HC expansion routes to in-place quota revision (ADR-001 Invariant 20)
-- ============================================================================

-- ── 1. Update _assign_and_deploy_emploc_core ────────────────────────────────
-- Base: 20262606000190_allow_add_emploc_in_pending_tab_for_all_authorized_assigners.sql
CREATE OR REPLACE FUNCTION public._assign_and_deploy_emploc_core(
  p_hr_emploc_id uuid,
  p_employee_no text,
  p_confirm_reuse boolean DEFAULT false,
  p_reuse_reason text DEFAULT NULL::text,
  p_actor_profile_id uuid DEFAULT NULL::uuid,
  p_source_fn text DEFAULT 'assign_and_deploy_core'::text
)
 RETURNS plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor_profile_id uuid := COALESCE(p_actor_profile_id, public.get_my_profile_id());
  v_actor_name       text := public.get_my_full_name();
  v_clean_id         text := btrim(COALESCE(p_employee_no, ''));
  v_emp              public.hr_emploc;
  v_app              public.applicants;
  v_pl               public.plantilla;
  v_existing_pl      public.plantilla;
  v_slot_id          uuid := NULL;
  v_slot_auth        jsonb;
  v_pool_slot_id     uuid := NULL;
  v_is_pool          boolean := false;
  v_pool_type_id     uuid;
  v_home_account_id  uuid;
  v_home_acct        public.accounts;
  v_formatted_name   text;
  v_norm_name        text;
  v_reg              public.employee_number_registry;
  v_match            jsonb;
  v_is_rehire        boolean := false;
  v_dup_reg          public.employee_number_registry;
  v_dup_match        jsonb;
  r_cand             RECORD;
  r_link             RECORD;
  v_contact_number   text;
BEGIN
  -- 1. Format validation (rejects empty, spaces, (PENDING), invalid chars)
  IF v_clean_id = '' OR upper(v_clean_id) = '(PENDING)' OR v_clean_id !~ '^[A-Za-z0-9._-]+$' THEN
    RAISE EXCEPTION 'INVALID_EMPLOYEE_ID: Employee number "%" is invalid.', v_clean_id
      USING ERRCODE = '22023';
  END IF;

  -- 2. Lock target HR Emploc row
  SELECT * INTO v_emp
  FROM public.hr_emploc
  WHERE id = p_hr_emploc_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'HR_RECORD_NOT_FOUND: HR record % does not exist.', p_hr_emploc_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_emp.status = 'Moved to Plantilla' THEN
    SELECT * INTO v_existing_pl FROM public.plantilla WHERE hr_emploc_id = p_hr_emploc_id LIMIT 1;
    IF v_existing_pl.id IS NOT NULL THEN
      RETURN v_existing_pl;
    END IF;
  END IF;

  -- 3. RBAC Check: Super Admin (100), Head Admin (90), HR Personnel (25), or authorized assigners
  IF NOT (
    public.i_have_full_access()
    OR public.get_my_role_level() IN (90, 25)
    OR (
      public.get_my_role_level() = 30
      AND v_emp.status = 'Pending Emploc'
    )
    OR (
      v_emp.status IN ('Pending', 'Pending Emploc')
      AND (
        public.i_have_full_access()
        OR public.get_my_role_level() >= 20
        OR v_emp.account = ANY(public.get_my_allowed_accounts())
        OR v_emp.account_id = ANY(public.get_my_allowed_account_ids())
      )
    )
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You do not have permission to assign employee numbers and deploy.'
      USING ERRCODE = '42501';
  END IF;

  -- 4. Scope Guard
  IF NOT public.i_have_full_access()
     AND NOT (v_emp.account = ANY(public.get_my_allowed_accounts()))
     AND NOT (v_emp.account_id = ANY(public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'OUT_OF_SCOPE: Account % is outside your scope.', v_emp.account
      USING ERRCODE = '42501';
  END IF;

  -- 5. Load applicant row for additional snapshots
  IF v_emp.applicant_id IS NOT NULL THEN
    SELECT * INTO v_app FROM public.applicants WHERE id = v_emp.applicant_id;
  END IF;

  -- Resolve inherited contact number
  v_contact_number := COALESCE(
    NULLIF(trim(v_emp.contact_number_snapshot), ''),
    NULLIF(trim(v_app.contact_number), '')
  );

  v_formatted_name := public.fn_format_employee_name_full(
    COALESCE(v_app.last_name, v_emp.last_name),
    COALESCE(v_app.first_name, v_emp.first_name),
    COALESCE(v_app.middle_name, v_emp.middle_name)
  );

  -- 6. Slot Authority checks
  v_is_pool := (COALESCE(v_emp.assignment_type::text, 'Stationary') = 'Pool');
  IF v_is_pool THEN
    SELECT wpr.pool_type_id, wpr.requesting_account_id
      INTO v_pool_type_id, v_home_account_id
    FROM public.workforce_pool_requests wpr
    WHERE wpr.id = v_emp.pool_request_id;
  ELSE
    IF v_emp.slot_id IS NOT NULL THEN
      v_slot_id := v_emp.slot_id;
    ELSIF v_emp.vcode IS NOT NULL THEN
      SELECT id INTO v_slot_id
      FROM public.plantilla_slots
      WHERE legacy_vcode = v_emp.vcode
        AND slot_status IN ('hr_processing', 'open', 'pipeline')
      ORDER BY slot_ordinal ASC
      LIMIT 1;
    END IF;
  END IF;

  -- 7. INSERT INTO PLANTILLA
  IF v_is_pool THEN
    SELECT * INTO v_home_acct FROM accounts WHERE id = COALESCE(v_home_account_id, v_emp.account_id);

    INSERT INTO plantilla (
      account,              account_id,
      store_id,             store_name,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,             last_name,
      civil_status,         date_of_birth,
      contact_no,
      sss_no,               philhealth_no,          pagibig_no,
      date_hired,           vacancy_id,              vacancy_code_snapshot,
      vcode,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      is_pool_employee,     pool_type_id,
      requesting_account,   requesting_account_id,   requesting_store_id,
      deployment_type,
      status,               tagged_at,
      moved_by_user_id,     created_by,              updated_by,
      created_at,           updated_at
    )
    VALUES (
      COALESCE(v_home_acct.account_name, v_emp.account), COALESCE(v_home_acct.id, v_emp.account_id),
      NULL, NULL,
      v_emp.position,           v_emp.position_id_snapshot,
      v_clean_id,               v_clean_id,
      v_formatted_name,         v_formatted_name,
      v_app.first_name,         v_app.middle_name,       v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_contact_number,
      v_emp.sss_snapshot,       v_emp.philhealth_snapshot,    v_emp.pagibig_snapshot,
      v_emp.hired_date,         v_emp.vacancy_id,             v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name,          v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot,  v_emp.area_name_snapshot,
      v_emp.id,
      true,                     v_pool_type_id,
      v_emp.account,            v_emp.account_id,             v_emp.store_id,
      'Pool',
      'Active',                 CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

  ELSIF v_emp.coverage_slot_id IS NOT NULL OR COALESCE(v_emp.assignment_type::text, 'Stationary') = 'Coverage' THEN
    INSERT INTO plantilla (
      account,              account_id,           chain_id,             province_id,
      store_id,             store_name,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,          last_name,
      civil_status,         date_of_birth,
      contact_no,
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
      v_emp.store_id, v_emp.store_name,
      v_emp.position, v_emp.position_id_snapshot,
      v_clean_id, v_clean_id,
      v_formatted_name, v_formatted_name,
      v_app.first_name, v_app.middle_name, v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_contact_number,
      v_emp.sss_snapshot, v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date, v_emp.vacancy_id, v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name, v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      v_emp.coverage_slot_id, v_emp.coverage_group_id,
      'Coverage',
      'Active', CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    IF v_emp.coverage_slot_id IS NOT NULL THEN
      PERFORM public.fn_occupy_coverage_slot(
        p_coverage_slot_id => v_emp.coverage_slot_id,
        p_plantilla_id     => v_pl.id,
        p_performed_by     => v_actor_profile_id,
        p_source_fn        => p_source_fn
      );
    END IF;

    PERFORM public.fn_sync_employee_store_allocations(v_clean_id);

  ELSIF COALESCE(v_emp.assignment_type::text, 'Stationary') = 'Roving' THEN
    INSERT INTO plantilla (
      account,              account_id,           chain_id,             province_id,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,          last_name,
      civil_status,         date_of_birth,
      contact_no,
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
      v_clean_id, v_clean_id,
      v_formatted_name, v_formatted_name,
      v_app.first_name, v_app.middle_name, v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_contact_number,
      v_emp.sss_snapshot, v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date,
      v_emp.hrco_name, v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      v_emp.roving_assignment_id,
      'Roving',
      'Active', CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    INSERT INTO public.plantilla_store_links (
      plantilla_id, roving_assignment_id, hr_emploc_store_link_id,
      vacancy_id, vcode, store_name, account,
      status, linked_at, linked_by, created_by, updated_by
    )
    SELECT
      v_pl.id, sl.roving_assignment_id, sl.id,
      sl.vacancy_id, sl.vcode, sl.store_name, sl.account,
      'Active', NOW(), v_actor_profile_id, v_actor_profile_id, v_actor_profile_id
    FROM public.hr_emploc_store_links sl
    WHERE sl.hr_emploc_id = v_emp.id
      AND sl.status = 'Confirmed'
      AND sl.deleted_at IS NULL
      AND sl.vcode IS NOT NULL
    ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL) DO NOTHING;

    PERFORM public.fn_sync_employee_store_allocations(v_clean_id);

  ELSE
    -- Pure stationary path
    INSERT INTO plantilla (
      account,              account_id,            chain_id,             store_id,
      store_name,           position,              position_id,
      province_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,           last_name,
      civil_status,         date_of_birth,
      contact_no,
      sss_no,               philhealth_no,          pagibig_no,
      date_hired,           vacancy_id,              vacancy_code_snapshot,
      vcode,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      deployment_type,
      status,               tagged_at,
      moved_by_user_id,     created_by,             updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_emp.account, v_emp.account_id, v_emp.chain_id, v_emp.store_id,
      v_emp.store_name, v_emp.position, v_emp.position_id_snapshot,
      v_emp.province_id,
      v_clean_id, v_clean_id,
      v_formatted_name, v_formatted_name,
      v_app.first_name, v_app.middle_name, v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_contact_number,
      v_emp.sss_snapshot, v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date, v_emp.vacancy_id, v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name, v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      'Stationary',
      'Active', CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    IF v_slot_id IS NOT NULL THEN
      PERFORM public.fn_set_slot_status(
        p_slot_id               => v_slot_id,
        p_new_status            => 'occupied',
        p_reason_code           => NULL,
        p_performed_by          => v_actor_profile_id,
        p_remarks               => 'Occupied by employee ' || v_clean_id,
        p_occupant_plantilla_id => v_pl.id
      );
    END IF;

    PERFORM public.fn_sync_employee_store_allocations(v_clean_id);
  END IF;

  -- 8. Mark HR Emploc row as Moved to Plantilla
  UPDATE public.hr_emploc
  SET
    status               = 'Moved to Plantilla',
    emploc_no            = v_clean_id,
    moved_to_plantilla_at = NOW(),
    moved_to_plantilla_by = v_actor_profile_id,
    updated_at           = NOW()
  WHERE id = p_hr_emploc_id;

  RETURN v_pl;
END;
$function$;

REVOKE ALL ON FUNCTION public._assign_and_deploy_emploc_core(uuid, text, boolean, text, uuid, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public._assign_and_deploy_emploc_core(uuid, text, boolean, text, uuid, text) TO service_role, authenticated;


-- ── 2. Update reopen_or_create_vacancy_for_plantilla ────────────────────────
-- Base: 20262606000091_archive_previous_applicants_on_vacancy_reopen.sql
CREATE OR REPLACE FUNCTION public.reopen_or_create_vacancy_for_plantilla(
  p_plantilla_id uuid,
  p_effective_date date,
  p_vacancy_type text DEFAULT 'Backfill'::text
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_plantilla          public.plantilla;
  v_vacancy_id         uuid;
  v_actor_id           uuid := COALESCE(public.get_current_profile_id(), public.get_my_profile_id(), auth.uid());
  v_actor_name         text;
  v_effective_vac_date date := COALESCE(p_effective_date, CURRENT_DATE);
BEGIN
  SELECT *
    INTO v_plantilla
  FROM public.plantilla
  WHERE id = p_plantilla_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla not found: %', p_plantilla_id;
  END IF;

  -- Resolve actor name for deterministic ownership attribution
  SELECT full_name INTO v_actor_name
  FROM public.users_profile
  WHERE id = v_actor_id
     OR auth_user_id = auth.uid()
  ORDER BY (id = v_actor_id) DESC
  LIMIT 1;
  v_actor_name := COALESCE(v_actor_name, 'System');

  -- Dynamic resolution of position_id if null or invalid
  IF v_plantilla.position_id IS NULL AND v_plantilla.position IS NOT NULL AND btrim(v_plantilla.position) <> '' THEN
    SELECT p.id INTO v_plantilla.position_id
    FROM public.positions p
    WHERE lower(btrim(p.position_name)) = lower(btrim(v_plantilla.position))
    LIMIT 1;
    IF v_plantilla.position_id IS NOT NULL THEN
      UPDATE public.plantilla
         SET position_id = v_plantilla.position_id
       WHERE id = v_plantilla.id;
    END IF;
  END IF;

  IF v_plantilla.position_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = v_plantilla.position_id
  ) THEN
    SELECT p.id INTO v_plantilla.position_id
    FROM public.positions p
    WHERE lower(btrim(p.position_name)) = lower(btrim(v_plantilla.position))
    LIMIT 1;
    IF v_plantilla.position_id IS NOT NULL THEN
      UPDATE public.plantilla
         SET position_id = v_plantilla.position_id
       WHERE id = v_plantilla.id;
    END IF;
  END IF;

  -- VCODE is the manpower slot identity.
  -- Reopen/reactivate existing slot first.
  SELECT id
    INTO v_vacancy_id
  FROM public.vacancies
  WHERE vcode = v_plantilla.vcode
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_vacancy_id IS NOT NULL THEN
    UPDATE public.vacancies
    SET
      status               = 'Open',
      vacancy_type         = COALESCE(p_vacancy_type, vacancy_type, 'Backfill'),
      vacant_date          = v_effective_vac_date,
      triggered_by_user_id = v_actor_id,
      triggered_by_name    = v_actor_name,
      source_plantilla_id  = v_plantilla.id,
      account              = v_plantilla.account,
      account_id           = v_plantilla.account_id,
      chain_id             = v_plantilla.chain_id,
      store_id             = v_plantilla.store_id,
      province_id          = v_plantilla.province_id,
      position             = v_plantilla.position,
      position_id          = v_plantilla.position_id,
      area_name            = COALESCE(v_plantilla.area_name_snapshot, v_plantilla.area),
      store_name           = v_plantilla.store_name,
      is_archived          = FALSE,
      archived_at          = NULL,
      deleted_at           = NULL,
      has_pending_closure  = FALSE,
      updated_at           = NOW(),
      updated_by           = v_actor_id
    WHERE id = v_vacancy_id;

    -- Archive any previous applicants under this vcode so the reopened vacancy is clean & unoccupied
    IF v_plantilla.vcode IS NOT NULL THEN
      UPDATE public.applicants
         SET is_archived = true,
             archived_at = NOW()
       WHERE vacancy_vcode = v_plantilla.vcode
         AND COALESCE(is_archived, false) = false;
    END IF;

    RETURN v_vacancy_id;
  END IF;

  IF v_plantilla.position_id IS NOT NULL THEN
    INSERT INTO public.vacancies (
      vcode,
      account,
      position,
      account_id,
      chain_id,
      store_id,
      province_id,
      area_name,
      position_id,
      vacant_date,
      vacancy_type,
      status,
      source_plantilla_id,
      store_name,
      created_at,
      updated_at,
      created_by,
      updated_by,
      triggered_by_user_id,
      triggered_by_name,
      required_headcount
    )
    SELECT
      v_plantilla.vcode,
      v_plantilla.account,
      p.position_name,
      v_plantilla.account_id,
      v_plantilla.chain_id,
      v_plantilla.store_id,
      v_plantilla.province_id,
      COALESCE(v_plantilla.area_name_snapshot, v_plantilla.area),
      p.id,
      v_effective_vac_date,
      COALESCE(p_vacancy_type, 'Backfill'),
      'Open',
      v_plantilla.id,
      v_plantilla.store_name,
      NOW(),
      NOW(),
      v_actor_id,
      v_actor_id,
      v_actor_id,
      v_actor_name,
      1
    FROM public.positions p
    WHERE p.id = v_plantilla.position_id
    RETURNING id INTO v_vacancy_id;
  END IF;

  IF v_vacancy_id IS NULL THEN
    INSERT INTO public.vacancies (
      vcode,
      account,
      position,
      account_id,
      chain_id,
      store_id,
      province_id,
      area_name,
      position_id,
      vacant_date,
      vacancy_type,
      status,
      source_plantilla_id,
      store_name,
      created_at,
      updated_at,
      created_by,
      updated_by,
      triggered_by_user_id,
      triggered_by_name,
      required_headcount
    ) VALUES (
      v_plantilla.vcode,
      v_plantilla.account,
      COALESCE(NULLIF(TRIM(v_plantilla.position), ''), 'UNSPECIFIED'),
      v_plantilla.account_id,
      v_plantilla.chain_id,
      v_plantilla.store_id,
      v_plantilla.province_id,
      COALESCE(v_plantilla.area_name_snapshot, v_plantilla.area),
      v_plantilla.position_id,
      v_effective_vac_date,
      COALESCE(p_vacancy_type, 'Backfill'),
      'Open',
      v_plantilla.id,
      v_plantilla.store_name,
      NOW(),
      NOW(),
      v_actor_id,
      v_actor_id,
      v_actor_id,
      v_actor_name,
      1
    ) RETURNING id INTO v_vacancy_id;
  END IF;

  -- Archive any previous applicants under this vcode so the reopened vacancy is clean & unoccupied
  IF v_plantilla.vcode IS NOT NULL THEN
    UPDATE public.applicants
       SET is_archived = true,
           archived_at = NOW()
     WHERE vacancy_vcode = v_plantilla.vcode
       AND COALESCE(is_archived, false) = false;
  END IF;

  RETURN v_vacancy_id;
END;
$function$;


-- ── 3. Update fn_plantilla_separation_to_vacancy ────────────────────────────
-- Base: 20262606000156_auto_separation_sync_v_kpi_and_allocation_cleanup.sql
CREATE OR REPLACE FUNCTION public.fn_plantilla_separation_to_vacancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link        RECORD;
  v_vac         public.vacancies%ROWTYPE;
  v_esa         RECORD;
  v_new_link_id uuid;
  v_hc          numeric;
  v_resolved_requirement_id uuid;
  v_link_status text;
  v_link_vcode  text;
  v_actor_id    uuid := COALESCE(public.get_current_profile_id(), public.get_my_profile_id(), auth.uid());
  v_actor_name  text;
  v_sep_date    date := COALESCE(NEW.date_of_separation, CURRENT_DATE);
BEGIN
  -- Trigger filter logic: include 'Pending Deactivation' in allowed originating status
  IF OLD.status NOT IN ('Active', 'On Leave', 'For Deactivation', 'Pending Deactivation')
    OR NEW.status NOT IN ('Resigned', 'AWOL', 'Endo', 'Terminated', 'Others',
                          'Inactive', 'Floating', 'For Deactivation')
    OR OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  SELECT full_name INTO v_actor_name
  FROM public.users_profile
  WHERE id = v_actor_id
     OR auth_user_id = auth.uid()
  ORDER BY (id = v_actor_id) DESC
  LIMIT 1;
  v_actor_name := COALESCE(v_actor_name, 'System');

  -- Dynamic resolution of position_id if null or invalid
  IF NEW.position_id IS NULL AND NEW.position IS NOT NULL AND btrim(NEW.position) <> '' THEN
    SELECT p.id INTO NEW.position_id
    FROM public.positions p
    WHERE lower(btrim(p.position_name)) = lower(btrim(NEW.position))
    LIMIT 1;
    IF NEW.position_id IS NOT NULL THEN
      UPDATE public.plantilla
         SET position_id = NEW.position_id
       WHERE id = NEW.id;
    END IF;
  END IF;

  IF NEW.position_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = NEW.position_id
  ) THEN
    SELECT p.id INTO NEW.position_id
    FROM public.positions p
    WHERE lower(btrim(p.position_name)) = lower(btrim(NEW.position))
    LIMIT 1;
    IF NEW.position_id IS NOT NULL THEN
      UPDATE public.plantilla
         SET position_id = NEW.position_id
       WHERE id = NEW.id;
    END IF;
  END IF;

  -- 1. Release the Coverage Group slot this employee occupied, if any.
  IF NEW.coverage_slot_id IS NOT NULL THEN
    UPDATE public.coverage_slots
       SET slot_status = 'open',
           current_occupant_plantilla_id = NULL,
           updated_at = NOW()
     WHERE id = NEW.coverage_slot_id
       AND current_occupant_plantilla_id = NEW.id;

    UPDATE public.hr_emploc
       SET deleted_at = NOW()
     WHERE coverage_slot_id = NEW.coverage_slot_id
       AND deleted_at IS NULL
       AND status = 'Moved to Plantilla';

  ELSIF NEW.coverage_group_id IS NOT NULL THEN
    UPDATE public.coverage_slots
       SET slot_status = 'open',
           current_occupant_plantilla_id = NULL,
           updated_at = NOW()
     WHERE coverage_group_id = NEW.coverage_group_id
       AND current_occupant_plantilla_id = NEW.id;

    UPDATE public.hr_emploc
       SET deleted_at = NOW()
     WHERE coverage_group_id = NEW.coverage_group_id
       AND deleted_at IS NULL
       AND status = 'Moved to Plantilla'
       AND coverage_slot_id IN (
         SELECT id FROM public.coverage_slots
          WHERE coverage_group_id = NEW.coverage_group_id
            AND current_occupant_plantilla_id IS NULL
       );
  END IF;

  -- ── Roving employee path ─────────────────────────────────────────────────
  IF COALESCE(NEW.deployment_type, '') = 'Roving' THEN

    v_link_status := CASE
      WHEN lower(COALESCE(NEW.separation_status, '')) IN ('awol','resigned','terminated','end of contract','endo','others')
        THEN 'Resigned'
      ELSE 'Backed Out'
    END;

    IF NEW.coverage_slot_id IS NOT NULL OR NEW.coverage_group_id IS NOT NULL THEN
      UPDATE public.plantilla_store_links
         SET status      = v_link_status,
             unlinked_at = NOW()
       WHERE plantilla_id = NEW.id
         AND status       = 'Active';

      UPDATE public.employee_store_allocations
         SET is_active     = false,
             effective_end = v_sep_date
       WHERE plantilla_id = NEW.id
         AND is_active    = true;

      RETURN NEW;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.plantilla_store_links
       WHERE plantilla_id = NEW.id AND status = 'Active'
    ) THEN
      FOR v_link IN
        SELECT * FROM public.plantilla_store_links
         WHERE plantilla_id = NEW.id AND status = 'Active'
      LOOP
        SELECT COALESCE(esa.filled_hc, 1)::numeric INTO v_hc
          FROM public.employee_store_allocations esa
         WHERE esa.plantilla_id        = NEW.id
           AND esa.vcode               = v_link.vcode
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
               SET status               = 'Open',
                   is_archived          = false,
                   archived_at          = NULL,
                   archived_by          = NULL,
                   vacant_date          = v_sep_date,
                   triggered_by_user_id = v_actor_id,
                   triggered_by_name    = v_actor_name,
                   required_headcount   = GREATEST(
                                         COALESCE(required_headcount, 0) + v_hc,
                                         1
                                       ),
                   updated_at           = NOW()
             WHERE id = v_vac.id;
          ELSE
            UPDATE public.vacancies
               SET required_headcount   = GREATEST(
                                         COALESCE(required_headcount, 0) + v_hc,
                                         1
                                       ),
                   vacant_date          = COALESCE(vacant_date, v_sep_date),
                   triggered_by_user_id = COALESCE(triggered_by_user_id, v_actor_id),
                   triggered_by_name    = COALESCE(triggered_by_name, v_actor_name),
                   updated_at           = NOW()
             WHERE id = v_vac.id;
          END IF;
        ELSE
          INSERT INTO public.vacancies (
            vcode, account, account_id, store_id, store_name, position, position_id,
            status, vacancy_type, required_headcount, employment_type,
            vacant_date, triggered_by_user_id, triggered_by_name,
            source, created_at, updated_at
          )
          SELECT
            v_link.vcode,
            NEW.account,
            NEW.account_id,
            s.id,
            s.store_name,
            COALESCE(p.position_name, NEW.position, 'UNSPECIFIED'),
            p.id,
            'Open',
            'Backfill',
            GREATEST(v_hc, 1),
            'Roving',
            v_sep_date,
            v_actor_id,
            v_actor_name,
            'plantilla',
            NOW(),
            NOW()
          FROM (SELECT 1) dummy
          LEFT JOIN public.positions p ON p.id = NEW.position_id
          LEFT JOIN public.stores s ON s.vcode = v_link.vcode
          RETURNING * INTO v_vac;

          UPDATE public.plantilla_store_links
             SET vacancy_id = v_vac.id
           WHERE id = v_link.id;
        END IF;

        UPDATE public.plantilla_store_links
           SET status      = v_link_status,
               unlinked_at = NOW()
         WHERE id = v_link.id;

        -- Archive previous applicants for this roving slot
        IF v_link.vcode IS NOT NULL THEN
          UPDATE public.applicants
             SET is_archived = true,
                 archived_at = NOW()
            WHERE vacancy_vcode = v_link.vcode
              AND COALESCE(is_archived, false) = false;
        END IF;

      END LOOP;
    END IF;

    UPDATE public.employee_store_allocations
       SET is_active     = false,
           effective_end = v_sep_date
     WHERE plantilla_id = NEW.id
       AND is_active    = true;

    RETURN NEW;
  END IF;

  -- ── Stationary employee path ─────────────────────────────────────────────
  PERFORM public.reopen_or_create_vacancy_for_plantilla(
    NEW.id,
    v_sep_date,
    'Backfill'
  );

  UPDATE public.employee_store_allocations
     SET is_active     = false,
         effective_end = v_sep_date
   WHERE plantilla_id = NEW.id
     AND is_active    = true;

  RETURN NEW;
END;
$function$;


-- ── 4. Update confirm_applicant_onboard ─────────────────────────────────────
-- Base: 20262606000189_security_audit_hardening_rls_rpcs_and_slot_authority.sql
CREATE OR REPLACE FUNCTION public.confirm_applicant_onboard(
  p_applicant_id uuid,
  p_last_name text DEFAULT NULL::text,
  p_first_name text DEFAULT NULL::text,
  p_middle_name text DEFAULT NULL::text,
  p_full_name text DEFAULT NULL::text,
  p_contact_number text DEFAULT NULL::text,
  p_remarks text DEFAULT NULL::text,
  p_roving_assignment_id uuid DEFAULT NULL::uuid,
  p_hired_by_user_id uuid DEFAULT NULL::uuid,
  p_endorsed_by_deployer_id uuid DEFAULT NULL::uuid,
  p_endorsed_by_name text DEFAULT NULL::text,
  p_hired_date date DEFAULT NULL::date,
  p_vacancy_requirement_id uuid DEFAULT NULL::uuid
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role        text    := public.get_my_role();
  v_role_level  integer := public.get_my_role_level();
  v_profile_id  uuid    := public.get_my_profile_id();
  v_actor_name  text    := public.get_my_full_name();
  v_hired_by_id uuid;
  v_app         public.applicants%ROWTYPE;
  v_vac         public.vacancies%ROWTYPE;
  v_hr          public.hr_emploc%ROWTYPE;
  v_is_roving   boolean;
  v_store_link_id uuid;
  v_late_result   jsonb;
  v_existing_plt      public.plantilla%ROWTYPE;
  v_roving_id         uuid;
  v_new_roving        boolean := false;
  v_plt_store_link_id uuid;
  v_existing_employee_no text;
  v_roving_hr_found   boolean := false;
  v_resolved_requirement_id uuid;
  v_slot_sync_result  jsonb;
  v_cg_store_id       uuid;
  v_target_slot       record;
  v_req_pos_id        uuid;
  v_req_pos_name      text;
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

  -- If applicant is bound to a Coverage Group, delegate to confirm_coverage_group_onboarding
  IF v_app.coverage_group_id IS NOT NULL THEN
    v_cg_store_id := v_vac.store_id;
    IF v_cg_store_id IS NULL AND v_app.vacancy_vcode IS NOT NULL THEN
      SELECT s.id INTO v_cg_store_id
        FROM public.stores s
       WHERE upper(s.vcode) = upper(v_app.vacancy_vcode)
       LIMIT 1;
    END IF;

    IF v_cg_store_id IS NOT NULL THEN
      RETURN public.confirm_coverage_group_onboarding(
        p_applicant_id       => p_applicant_id,
        p_selected_store_ids => ARRAY[v_cg_store_id],
        p_hired_by_user_id   => p_hired_by_user_id,
        p_hired_date         => p_hired_date,
        p_remarks            => p_remarks
      );
    END IF;
  END IF;

  IF v_vac.id IS NULL THEN
    RAISE EXCEPTION 'vacancy % not found', v_app.vacancy_vcode
      USING ERRCODE = 'P0002';
  END IF;

  -- SEC-02 Scope Guard: verify target vacancy belongs to caller's allowed accounts
  IF NOT public.i_have_full_access()
     AND NOT (v_vac.account = ANY(public.get_my_allowed_accounts()))
     AND NOT (v_vac.account_id = ANY(public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: vacancy % is outside caller account scope', v_vac.vcode
      USING ERRCODE = '42501';
  END IF;

  v_is_roving := COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL;

  -- ── Idempotent Guard ──
  IF v_app.status = 'Confirmed Onboard' THEN
    IF v_is_roving THEN
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
         AND applicant_id = p_applicant_id
         AND deleted_at IS NULL
       LIMIT 1;
    ELSE
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE applicant_id = p_applicant_id
         AND deleted_at IS NULL
         AND (
           vcode = v_vac.vcode
           OR (applicant_name = v_app.full_name AND vcode = v_app.vacancy_vcode)
         )
       ORDER BY created_at DESC LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
      'ok',               true,
      'applicant_id',     v_app.id,
      'applicant_status', v_app.status,
      'hr_emploc_id',     v_hr.id,
      'vcode',            v_app.vacancy_vcode,
      'idempotent',       true
    );
  END IF;

  -- Resolve requirement ID and specific requested position
  v_resolved_requirement_id := COALESCE(p_vacancy_requirement_id, v_app.vacancy_requirement_id);

  IF v_resolved_requirement_id IS NULL AND NOT v_is_roving THEN
    SELECT vr.id INTO v_resolved_requirement_id
      FROM public.vacancy_requirements vr
     WHERE vr.vacancy_id = v_vac.id
       AND GREATEST(
             (SELECT count(*) FROM public.plantilla p
               WHERE p.vacancy_requirement_id = vr.id
                 AND p.status = 'Active'
                 AND COALESCE(p.is_deleted, false) = false),
             (SELECT count(*) FROM public.applicants a
               WHERE a.vacancy_requirement_id = vr.id
                 AND a.status = 'Confirmed Onboard'
                 AND COALESCE(a.is_archived, false) = false
                 AND a.id <> p_applicant_id)
           ) < vr.hc_needed
     ORDER BY vr.created_at
     LIMIT 1;

    IF v_resolved_requirement_id IS NULL THEN
      SELECT id INTO v_resolved_requirement_id
        FROM public.vacancy_requirements
       WHERE vacancy_id = v_vac.id
       ORDER BY created_at
       LIMIT 1;
    END IF;
  END IF;

  -- Look up custom position if requirement specified
  IF v_resolved_requirement_id IS NOT NULL THEN
    SELECT vr.position_id, p.position_name
      INTO v_req_pos_id, v_req_pos_name
      FROM public.vacancy_requirements vr
      JOIN public.positions p ON p.id = vr.position_id
     WHERE vr.id = v_resolved_requirement_id;
  END IF;

  IF p_hired_by_user_id IS NOT NULL THEN
    v_hired_by_id := p_hired_by_user_id;
  ELSE
    v_hired_by_id := public.get_my_auth_uid();
  END IF;

  UPDATE public.applicants
     SET status               = 'Confirmed Onboard',
         last_name            = COALESCE(p_last_name,      last_name),
         first_name           = COALESCE(p_first_name,     first_name),
         middle_name          = COALESCE(p_middle_name,    middle_name),
         full_name            = COALESCE(p_full_name,      full_name),
         contact_number       = COALESCE(p_contact_number, contact_number),
         remarks              = COALESCE(p_remarks,        remarks),
         hired_date           = COALESCE(p_hired_date,     hired_date),
         hired_by             = v_hired_by_id::text,
         roving_assignment_id = COALESCE(
                                  p_roving_assignment_id,
                                  roving_assignment_id
                                ),
         vacancy_requirement_id = COALESCE(
                                    v_resolved_requirement_id,
                                    vacancy_requirement_id
                                  ),
         last_activity_at     = NOW(),
         last_activity_by     = v_profile_id,
         updated_at           = NOW()
   WHERE id = p_applicant_id;

  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id;

  -- Option A Fast-Track for existing Active Plantilla employee in same account
  SELECT plt.* INTO v_existing_plt
    FROM public.plantilla plt
   WHERE plt.account = v_vac.account
     AND (
       plt.employee_no ILIKE v_app.full_name
       OR LOWER(TRIM(plt.employee_name)) = LOWER(TRIM(v_app.full_name))
     )
     AND plt.status IN ('Active', 'On Leave')
     AND NOT COALESCE(plt.is_deleted, false)
     AND NOT COALESCE(plt.is_archived, false)
     AND plt.employee_no IS NOT NULL
   LIMIT 1
  FOR UPDATE;

  IF v_existing_plt.id IS NOT NULL THEN
    v_roving_id := COALESCE(v_existing_plt.roving_assignment_id, p_roving_assignment_id, v_app.roving_assignment_id);
    IF v_roving_id IS NULL AND v_existing_plt.coverage_slot_id IS NULL THEN
      INSERT INTO public.roving_assignments (
        master_applicant_id, account, account_id,
        primary_vcode, label, created_by, updated_by
      ) VALUES (
        v_app.id, v_vac.account, v_vac.account_id,
        COALESCE(v_existing_plt.vcode, v_vac.vcode),
        v_app.full_name,
        v_profile_id, v_profile_id
      ) RETURNING id INTO v_roving_id;

      UPDATE public.plantilla
         SET roving_assignment_id = v_roving_id,
             deployment_type      = 'Roving',
             updated_at           = NOW(),
             updated_by           = v_profile_id
       WHERE id = v_existing_plt.id;
    END IF;

    INSERT INTO public.plantilla_store_links (
      plantilla_id, roving_assignment_id, vacancy_id, vcode,
      store_name, account, status, linked_at, linked_by,
      created_by, updated_by
    ) VALUES (
      v_existing_plt.id,
      v_roving_id,
      v_vac.id,
      v_vac.vcode,
      v_vac.store_name,
      v_vac.account,
      'Active',
      NOW(),
      v_profile_id,
      v_profile_id,
      v_profile_id
    )
    ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL)
    DO UPDATE SET status = 'Active', unlinked_at = NULL, updated_at = NOW()
    RETURNING id INTO v_plt_store_link_id;

    FOR v_target_slot IN
      SELECT id, slot_status
        FROM public.plantilla_slots
       WHERE legacy_vcode = v_vac.vcode
         AND closed_at IS NULL
         AND slot_status IN ('open', 'pipeline', 'hr_processing')
    LOOP
      IF v_target_slot.slot_status = 'pipeline' THEN
        PERFORM public.fn_set_slot_status(
          p_slot_id               => v_target_slot.id,
          p_new_status            => 'hr_processing',
          p_reason_code           => 'REPLACEMENT',
          p_performed_by          => v_profile_id,
          p_remarks               => 'confirm_applicant_onboard: Option A fast-track pipeline->hr_processing for ' || v_vac.vcode,
          p_occupant_plantilla_id => NULL
        );
      END IF;

      PERFORM public.fn_set_slot_status(
        p_slot_id               => v_target_slot.id,
        p_new_status            => 'occupied',
        p_reason_code           => NULL,
        p_performed_by          => v_profile_id,
        p_remarks               => 'confirm_applicant_onboard: Option A fast-track occupied by plantilla ' || v_existing_plt.id::text,
        p_occupant_plantilla_id => v_existing_plt.id
      );
    END LOOP;

    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_profile_id
     WHERE id = v_vac.id;

    PERFORM public.fn_sync_employee_store_allocations(v_existing_plt.employee_no);

    RETURN jsonb_build_object(
      'ok',                      true,
      'applicant_id',            v_app.id,
      'applicant_status',        v_app.status,
      'hr_emploc_id',            NULL,
      'plantilla_id',            v_existing_plt.id,
      'plantilla_store_link_id', v_plt_store_link_id,
      'vcode',                   v_vac.vcode,
      'hired_by_user_id',        v_hired_by_id,
      'is_roving',               true,
      'fast_tracked',            true,
      'skipped_hr_emploc',       true
    );
  END IF;

  SELECT * INTO v_hr
    FROM public.hr_emploc
   WHERE applicant_id = p_applicant_id
     AND deleted_at IS NULL
   LIMIT 1;

  IF v_hr.id IS NOT NULL THEN
    UPDATE public.hr_emploc
       SET hr_status              = COALESCE(hr_status, 'Pending'),
           vacancy_requirement_id = COALESCE(vacancy_requirement_id, v_resolved_requirement_id),
           position_id_snapshot   = COALESCE(v_req_pos_id, v_hr.position_id_snapshot, v_vac.position_id),
           position               = COALESCE(v_req_pos_name, v_hr.position, v_vac.position),
           updated_at             = NOW()
      WHERE id = v_hr.id
     RETURNING * INTO v_hr;
  ELSE
    IF NOT v_is_roving THEN
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
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
        v_vac.atl_user_id,
        COALESCE(v_req_pos_id, v_vac.position_id),
        COALESCE(v_req_pos_name, v_vac.position),
        v_vac.store_name, v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Stationary'::public.hr_emploc_assignment_type,
        NULL, '[]'::jsonb,
        v_resolved_requirement_id
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
      'vacancy_requirement_id',     v_resolved_requirement_id,
      'movement_at',                NOW()
    )
  );

  RETURN jsonb_build_object(
    'ok',                      true,
    'applicant_id',            v_app.id,
    'applicant_status',        v_app.status,
    'hr_emploc_id',            v_hr.id,
    'vcode',                   v_vac.vcode,
    'hired_by_user_id',        v_hired_by_id,
    'is_roving',               v_is_roving
  );
END;
$function$;


-- ── 5. Update create_plantilla_slot_from_request ────────────────────────────
-- Base: 20262606000142_mixed_stationary_roving_hc_and_nsr_vacancy.sql
CREATE OR REPLACE FUNCTION public.create_plantilla_slot_from_request(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role               text := public.get_my_role();
  v_req                public.headcount_requests%ROWTYPE;
  v_account            public.accounts%ROWTYPE;
  v_store              public.stores%ROWTYPE;
  v_position           public.positions%ROWTYPE;
  v_coverage_group     public.coverage_groups%ROWTYPE;
  v_store_name         text;
  v_store_id           uuid;
  v_vcode              text;
  v_vcodes             text[];
  v_plantilla_id       uuid;
  v_vacancy_id         uuid;
  v_first_plantilla_id uuid;
  v_count              integer;
  i                    integer;
  v_triggered_by_id    uuid;
  v_triggered_by_name  text;
  v_hrco_user_id       uuid;
  v_hrco_name          text;
  v_group_id           uuid;
  v_group_name         text;
  v_slot_result        jsonb;
  v_max_ordinal        integer;
  -- store-array path
  v_hc_store_row       public.hc_request_stores%ROWTYPE;
  v_new_cg_id          uuid;
  v_cg_code            text;
  v_store_vcodes       jsonb := '[]'::jsonb;
  v_stores_added       integer := 0;
  v_store_row          public.stores%ROWTYPE;
  -- stationary path VCODE reuse fields
  v_reused_vcode       boolean := false;
  v_vr_id              uuid;
BEGIN
  IF NOT (v_role IN ('Encoder', 'Super Admin', 'Head Admin')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  PERFORM public.fn_assert_freeze_inactive('recruitment_freeze');

  SELECT * INTO v_req
  FROM public.headcount_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  IF v_req.status <> 'approved_pending_vcode' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_approved', 'current', v_req.status);
  END IF;

  v_count := COALESCE(v_req.headcount_needed, 1);

  IF v_count < 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_headcount_needed');
  END IF;

  IF v_count > 20 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'headcount_limit_exceeded', 'max', 20);
  END IF;

  -- Hard guard for position_id validity
  IF NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = v_req.position_id
  ) THEN
    RAISE EXCEPTION 'Invalid position_id: %', v_req.position_id;
  END IF;

  SELECT * INTO v_account FROM public.accounts WHERE id = v_req.account_id;
  IF v_account.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'account_id');
  END IF;

  SELECT * INTO v_position FROM public.positions WHERE id = v_req.position_id;
  IF v_position.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'position_id');
  END IF;

  v_triggered_by_id := public.get_current_profile_id();
  SELECT full_name INTO v_triggered_by_name
  FROM public.users_profile WHERE id = v_triggered_by_id;

  v_group_id := COALESCE(v_req.group_id, v_account.group_id);
  SELECT group_name INTO v_group_name FROM public.groups WHERE id = v_group_id;

  v_hrco_user_id := v_account.hrco_user_id;
  IF v_hrco_user_id IS NOT NULL THEN
    SELECT full_name INTO v_hrco_name
    FROM public.users_profile WHERE id = v_hrco_user_id;
  END IF;

  -- ── Detect roving path ─────────────────────────────────────────────────────
  IF lower(coalesce(v_req.workforce_type, 'stationary')) = 'roving' THEN

    -- Check if this is the store-array path
    IF EXISTS (
      SELECT 1 FROM public.hc_request_stores WHERE request_id = p_request_id LIMIT 1
    ) THEN
      -- ══ ROVING STORE-ARRAY PATH (ADR-003 ATOMIC STORE PROVISIONING) ═════

      -- Step 1.5: Atomic Store Provisioning for unlisted/new stores in hc_request_stores
      FOR v_hc_store_row IN
        SELECT * FROM public.hc_request_stores
        WHERE request_id = p_request_id
          AND (is_new_store = true OR store_id IS NULL)
        ORDER BY sort_order ASC
      LOOP
        -- Check if an active store with the exact same name already exists in this account (idempotency guard)
        SELECT * INTO v_store_row
        FROM public.stores
        WHERE account_id = v_req.account_id
          AND lower(trim(store_name)) = lower(trim(COALESCE(v_hc_store_row.store_name, v_hc_store_row.store_name_snapshot)))
          AND coalesce(is_active, true) = true
        LIMIT 1;

        IF v_store_row.id IS NOT NULL THEN
          v_store_id := v_store_row.id;
        ELSE
          INSERT INTO public.stores (
            account_id,
            group_id,
            store_name,
            area_city,
            province,
            area_province,
            island_group,
            is_active,
            status,
            created_by,
            approved_by,
            approved_at
          ) VALUES (
            v_req.account_id,
            v_group_id,
            COALESCE(v_hc_store_row.store_name, v_hc_store_row.store_name_snapshot),
            COALESCE(v_hc_store_row.area_city, v_hc_store_row.city_snapshot),
            COALESCE(v_hc_store_row.area_province, v_hc_store_row.province_snapshot),
            COALESCE(v_hc_store_row.area_province, v_hc_store_row.province_snapshot),
            COALESCE(v_hc_store_row.island_group, v_hc_store_row.island_group_snapshot),
            true,
            'active',
            v_req.requested_by_user_id,
            v_triggered_by_id,
            now()
          ) RETURNING id INTO v_store_id;
        END IF;

        UPDATE public.hc_request_stores
        SET store_id = v_store_id,
            created_store_id = v_store_id
        WHERE id = v_hc_store_row.id;
      END LOOP;

      v_vcodes := ARRAY[]::text[];

      -- Step 1: Create the Coverage Group (structure only)
      v_new_cg_id := gen_random_uuid();
      v_cg_code   := public.fn_generate_cgcode_for_account(v_req.account_id);

      INSERT INTO public.coverage_groups (
        id,
        account_id,
        position_id,
        coverage_code,
        area_name,
        employment_type,
        status,
        required_headcount,
        created_by
      ) VALUES (
        v_new_cg_id,
        v_req.account_id,
        v_req.position_id,
        v_cg_code,
        COALESCE(v_req.area, ''),
        COALESCE(v_req.employment_type, 'Roving'),
        'open',
        v_count,
        v_triggered_by_id
      );

      -- Step 2: For each store in hc_request_stores, create VCode + Vacancy + Slot
      FOR v_hc_store_row IN
        SELECT * FROM public.hc_request_stores
        WHERE request_id = p_request_id
        ORDER BY sort_order ASC
      LOOP
        SELECT * INTO v_store_row FROM public.stores WHERE id = v_hc_store_row.store_id;

        -- Track highest existing ordinal on this VCODE before vacancy upsert (ohm#phase2-mixed-roving-hc)
        -- Reuse existing VCODE for store if active vacancy exists
        v_vcode := public.find_reusable_store_vcode(
          v_req.account_id,
          v_hc_store_row.store_id,
          COALESCE(v_hc_store_row.store_name, v_hc_store_row.store_name_snapshot)
        );

        IF v_vcode IS NULL THEN
          v_vcode := public.generate_vcode_for_account(v_req.account_id);

          -- Sync this new VCode to public.stores.vcode (fix: ohm#9x4p2k7q)
          IF v_hc_store_row.store_id IS NOT NULL THEN
            UPDATE public.stores
            SET vcode = v_vcode
            WHERE id = v_hc_store_row.store_id
              AND (vcode IS NULL OR trim(vcode) = '');
          END IF;
        END IF;

        v_vcodes := array_append(v_vcodes, v_vcode);

        SELECT COALESCE(MAX(slot_ordinal), 0)
        INTO v_max_ordinal
        FROM public.plantilla_slots
        WHERE legacy_vcode = v_vcode;

        -- Upsert vacancy for this store
        INSERT INTO public.vacancies (
          vcode, account, position, status,
          account_id, store_id, position_id, group_id,
          area_name, store_name, vacant_date,
          required_headcount, source_plantilla_id,
          vacancy_type, employment_type, urgency_level,
          target_fill_date, triggered_by_user_id, triggered_by_name,
          hrco_user_id, hrco_name,
          source, source_headcount_request_id,
          area_city, province, store_branch,
          chain, chain_id,
          created_by, updated_by
        )
        SELECT
          v_vcode,
          v_account.account_name,
          p.position_name,
          'Open',
          v_account.id,
          v_hc_store_row.store_id,
          p.id,
          v_group_id,
          COALESCE(v_hc_store_row.area_province, v_hc_store_row.province_snapshot, v_store_row.province, v_store_row.area_province),
          COALESCE(v_hc_store_row.store_name, v_hc_store_row.store_name_snapshot, v_store_row.store_name),
          COALESCE(v_req.vacant_date, CURRENT_DATE),
          1,  -- 1 HC per store; total coverage HC = v_count slots on the CG
          NULL,
          CASE WHEN v_req.request_type = 'Replacement' THEN 'Replacement' ELSE 'New' END,
          COALESCE(v_req.employment_type, 'Roving'),
          v_req.urgency,
          v_req.target_fill_date,
          v_triggered_by_id, v_triggered_by_name,
          v_hrco_user_id, v_hrco_name,
          'hc_request', p_request_id,
          COALESCE(v_hc_store_row.area_city, v_hc_store_row.city_snapshot, v_store_row.area_city),
          COALESCE(v_hc_store_row.area_province, v_hc_store_row.province_snapshot, v_store_row.province, v_store_row.area_province),
          v_store_row.store_branch,
          v_group_name, v_group_id,
          v_triggered_by_id, v_triggered_by_id
        FROM public.positions p
        WHERE p.id = v_req.position_id
        ON CONFLICT (vcode) DO UPDATE
          SET required_headcount = public.vacancies.required_headcount + 1,
              updated_by = v_triggered_by_id
        RETURNING id INTO v_vacancy_id;

        -- Create or adopt distinct roving plantilla_slots for this request (ohm#phase2-mixed-roving-hc)
        -- Never alters existing stationary slots (slot_ordinal <= v_max_ordinal).
        IF EXISTS (
          SELECT 1 FROM public.plantilla_slots
          WHERE legacy_vcode = v_vcode
            AND slot_ordinal > v_max_ordinal
          LIMIT 1
        ) THEN
          UPDATE public.plantilla_slots
          SET store_id             = COALESCE(store_id, v_hc_store_row.store_id),
              is_roving            = true,
              employment_type      = COALESCE(v_req.employment_type, 'Roving'),
              source_hc_request_id = p_request_id,
              updated_at           = now(),
              updated_by           = v_triggered_by_id
          WHERE legacy_vcode = v_vcode
            AND slot_ordinal > v_max_ordinal;
        ELSE
          IF NOT EXISTS (
            SELECT 1 FROM public.plantilla_slots
            WHERE legacy_vcode = v_vcode
              AND source_hc_request_id = p_request_id
            LIMIT 1
          ) THEN
            PERFORM public.fn_create_slots_from_hc_request(p_request_id, 1, v_vcode);
          END IF;

          UPDATE public.plantilla_slots
          SET store_id        = COALESCE(store_id, v_hc_store_row.store_id),
              is_roving       = true,
              employment_type = COALESCE(v_req.employment_type, 'Roving'),
              updated_at      = now(),
              updated_by      = v_triggered_by_id
          WHERE legacy_vcode = v_vcode
            AND source_hc_request_id = p_request_id;
        END IF;

        -- Add store to coverage_group_stores
        INSERT INTO public.coverage_group_stores (
          coverage_group_id,
          store_id,
          is_anchor,
          added_by
        ) VALUES (
          v_new_cg_id,
          v_hc_store_row.store_id,
          (v_stores_added = 0),
          v_triggered_by_id
        )
        ON CONFLICT DO NOTHING;

        v_stores_added := v_stores_added + 1;
      END LOOP;

      -- Step 3: Create coverage slots for the overall CG demand
      SELECT COALESCE(MAX(slot_ordinal), 0)
        INTO v_max_ordinal
      FROM public.coverage_slots
      WHERE coverage_group_id = v_new_cg_id;

      INSERT INTO public.coverage_slots (coverage_group_id, slot_ordinal, slot_status)
      SELECT v_new_cg_id, v_max_ordinal + gs.ord, 'open'
      FROM generate_series(1, v_count) AS gs(ord);

      -- Step 4: Finalise the HC request
      UPDATE public.headcount_requests
      SET status                      = 'completed',
          vacancy_created             = true,
          slot_created_by_user_id     = v_triggered_by_id,
          slot_created_at             = NOW(),
          coverage_group_id           = v_new_cg_id,
          coverage_group_code_snapshot = v_cg_code,
          created_vcode               = NULL,
          created_vcodes              = v_vcodes
      WHERE id = p_request_id;

      RETURN jsonb_build_object(
        'ok',                    true,
        'request_id',            p_request_id,
        'workforce_type',        'roving',
        'path',                  'store_array',
        'coverage_group_id',     v_new_cg_id,
        'coverage_code',         v_cg_code,
        'stores_processed',      v_stores_added,
        'vcodes',                v_vcodes,
        'vcode_count',           array_length(v_vcodes, 1),
        'coverage_slots_created', v_count,
        'vacancy_created',       true
      );

    ELSE
      -- ══ OLD ROVING PATH: add coverage slots to existing CG ══
      IF v_req.coverage_group_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'coverage_group_required_for_roving');
      END IF;

      SELECT * INTO v_coverage_group
      FROM public.coverage_groups
      WHERE id = v_req.coverage_group_id
        AND account_id = v_req.account_id
        AND archived_at IS NULL
      FOR UPDATE;

      IF v_coverage_group.id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'coverage_group_id');
      END IF;

      IF v_coverage_group.position_id IS NOT NULL AND v_coverage_group.position_id <> v_req.position_id THEN
        RETURN jsonb_build_object('ok', false, 'error', 'coverage_group_position_mismatch');
      END IF;

      SELECT COALESCE(MAX(slot_ordinal), 0)
        INTO v_max_ordinal
      FROM public.coverage_slots
      WHERE coverage_group_id = v_coverage_group.id;

      INSERT INTO public.coverage_slots (coverage_group_id, slot_ordinal, slot_status)
      SELECT v_coverage_group.id, v_max_ordinal + gs.ord, 'open'
      FROM generate_series(1, v_count) AS gs(ord);

      UPDATE public.coverage_groups
      SET required_headcount = required_headcount + v_count,
          status = 'open'
      WHERE id = v_coverage_group.id;

      UPDATE public.headcount_requests
      SET status                      = 'completed',
          vacancy_created             = true,
          slot_created_by_user_id     = v_triggered_by_id,
          slot_created_at             = NOW(),
          coverage_group_code_snapshot = COALESCE(coverage_group_code_snapshot, v_coverage_group.coverage_code),
          created_vcode               = NULL,
          created_vcodes              = ARRAY[]::text[]
      WHERE id = p_request_id;

      RETURN jsonb_build_object(
        'ok',                    true,
        'request_id',            p_request_id,
        'headcount_created',     v_count,
        'workforce_type',        'roving',
        'path',                  'coverage_group',
        'coverage_group_id',     v_coverage_group.id,
        'coverage_code',         v_coverage_group.coverage_code,
        'coverage_slots_created', v_count,
        'vacancy_created',       true
      );
    END IF;
  END IF;

  -- ── Floating path ──────────────────────────────────────────────────────────
  IF lower(coalesce(v_req.workforce_type, 'stationary')) = 'floating' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'floating_workforce_not_enabled');
  END IF;

  -- ── Stationary path ────────────────────────────────────────────────────────
  IF v_req.store_id IS NOT NULL THEN
    SELECT * INTO v_store FROM public.stores WHERE id = v_req.store_id;
  END IF;

  v_store_name := NULLIF(TRIM(COALESCE(v_store.store_name, v_req.store_name_snapshot)), '');
  v_store_id   := v_store.id;

  IF v_store_name IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'store_name');
  END IF;

  -- ── 1-store-1-VCODE reuse check ───────────────────────────────────────────
  v_vcode := public.find_reusable_store_vcode(v_account.id, v_store_id, v_store_name);

  IF v_vcode IS NOT NULL THEN
    v_reused_vcode := true;

    SELECT id INTO v_vacancy_id
    FROM public.vacancies
    WHERE vcode                          = v_vcode
      AND COALESCE(is_archived, false)   = false
      AND deleted_at                     IS NULL
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_vacancy_id IS NOT NULL THEN
      UPDATE public.vacancies
      SET required_headcount = required_headcount + v_count,
          status             = 'Open',
          updated_by         = v_triggered_by_id,
          updated_at         = now()
      WHERE id = v_vacancy_id;
    ELSE
      INSERT INTO public.vacancies (
        vcode, account, position, status,
        account_id, store_id, position_id, group_id,
        area_name, store_name, vacant_date,
        required_headcount, source_plantilla_id,
        vacancy_type, employment_type, urgency_level,
        target_fill_date, triggered_by_user_id, triggered_by_name,
        hrco_user_id, hrco_name,
        source, source_headcount_request_id,
        area_city, province, store_branch,
        chain, chain_id,
        created_by, updated_by
      )
      SELECT
        v_vcode, v_account.account_name, p.position_name, 'Open',
        v_account.id, v_store_id, p.id, v_group_id,
        COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
        v_store_name,
        COALESCE(v_req.vacant_date, CURRENT_DATE),
        v_count,
        NULL,
        CASE WHEN v_req.request_type = 'Replacement' THEN 'Replacement' ELSE 'New' END,
        v_req.employment_type, v_req.urgency, v_req.target_fill_date,
        v_triggered_by_id, v_triggered_by_name,
        v_hrco_user_id, v_hrco_name,
        'hc_request', p_request_id,
        COALESCE(v_store.area_city, v_req.city_municipality),
        COALESCE(v_store.province, NULLIF(TRIM(v_req.area), '')),
        v_store.store_branch,
        v_group_name, v_group_id,
        v_triggered_by_id, v_triggered_by_id
      FROM public.positions p
      WHERE p.id = v_req.position_id
      RETURNING id INTO v_vacancy_id;

      -- Sync this new VCode to public.stores.vcode (fix: ohm#9x4p2k7q)
      IF v_store_id IS NOT NULL THEN
        UPDATE public.stores
        SET vcode = v_vcode
        WHERE id = v_store_id
          AND (vcode IS NULL OR trim(vcode) = '');
      END IF;
    END IF;

  ELSE
    v_vcode := public.generate_vcode_for_account(v_account.id);

    INSERT INTO public.vacancies (
      vcode, account, position, status,
      account_id, store_id, position_id, group_id,
      area_name, store_name, vacant_date,
      required_headcount, source_plantilla_id,
      vacancy_type, employment_type, urgency_level,
      target_fill_date, triggered_by_user_id, triggered_by_name,
      hrco_user_id, hrco_name,
      source, source_headcount_request_id,
      area_city, province, store_branch,
      chain, chain_id,
      created_by, updated_by
    )
    SELECT
      v_vcode, v_account.account_name, p.position_name, 'Open',
      v_account.id, v_store_id, p.id, v_group_id,
      COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
      v_store_name,
      COALESCE(v_req.vacant_date, CURRENT_DATE),
      v_count,
      NULL,
      CASE WHEN v_req.request_type = 'Replacement' THEN 'Replacement' ELSE 'New' END,
      v_req.employment_type, v_req.urgency, v_req.target_fill_date,
      v_triggered_by_id, v_triggered_by_name,
      v_hrco_user_id, v_hrco_name,
      'hc_request', p_request_id,
      COALESCE(v_store.area_city, v_req.city_municipality),
      COALESCE(v_store.province, NULLIF(TRIM(v_req.area), '')),
      v_store.store_branch,
      v_group_name, v_group_id,
      v_triggered_by_id, v_triggered_by_id
    FROM public.positions p
    WHERE p.id = v_req.position_id
    RETURNING id INTO v_vacancy_id;

    -- Sync this new VCode to public.stores.vcode (fix: ohm#9x4p2k7q)
    IF v_store_id IS NOT NULL THEN
      UPDATE public.stores
      SET vcode = v_vcode
      WHERE id = v_store_id
        AND (vcode IS NULL OR trim(vcode) = '');
    END IF;
  END IF;

  v_vcodes := ARRAY[v_vcode];

  BEGIN
    SELECT id INTO v_vr_id
    FROM public.vacancy_requirements
    WHERE vacancy_id = v_vacancy_id
      AND position_id = v_position.id
    FOR UPDATE;

    IF v_vr_id IS NOT NULL THEN
      UPDATE public.vacancy_requirements
      SET hc_needed = hc_needed + v_count
      WHERE id = v_vr_id;
    ELSE
      INSERT INTO public.vacancy_requirements (
        vacancy_id, position_id, employment_type, hc_needed, hc_filled,
        source_headcount_request_id
      ) VALUES (
        v_vacancy_id, v_position.id, v_req.employment_type, v_count, 0,
        p_request_id
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'vacancy_requirements sync failed for request % (vacancy %, position %): %',
      p_request_id, v_vacancy_id, v_position.id, SQLERRM;
  END;

  -- ── Plantilla (VACANT SLOT) rows ──
  FOR i IN 1..v_count LOOP
    INSERT INTO public.plantilla (
      employee_name, employee_no,
      account, status, vcode, position,
      account_id, store_id, area, position_id,
      store_name, deployment_type,
      source_headcount_request_id,
      chain_id,
      created_by, updated_by, tagged_at
    ) VALUES (
      '(VACANT SLOT)', '(PENDING)',
      v_account.account_name, 'Inactive', v_vcode, v_position.position_name,
      v_account.id, v_store_id,
      COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
      v_position.id,
      v_store_name, v_req.employment_type,
      p_request_id,
      v_group_id,
      v_triggered_by_id, v_triggered_by_id, CURRENT_DATE
    ) RETURNING id INTO v_plantilla_id;

    IF v_first_plantilla_id IS NULL THEN
      v_first_plantilla_id := v_plantilla_id;
    END IF;
  END LOOP;

  -- Link vacancy back to first plantilla if this was a new vacancy
  IF NOT v_reused_vcode THEN
    UPDATE public.vacancies
    SET source_plantilla_id = v_first_plantilla_id,
        updated_by          = v_triggered_by_id
    WHERE id = v_vacancy_id;
  END IF;

  IF v_reused_vcode THEN
    v_slot_result := public.fn_create_slots_from_hc_request(p_request_id, v_count, v_vcode);
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.plantilla_slots
      WHERE legacy_vcode = v_vcode
      LIMIT 1
    ) THEN
      UPDATE public.plantilla_slots
      SET source_hc_request_id = p_request_id,
          updated_by           = v_triggered_by_id,
          updated_at           = now()
      WHERE legacy_vcode = v_vcode
        AND source_hc_request_id IS NULL;

      v_slot_result := jsonb_build_object(
        'ok',      true,
        'adopted', true,
        'hint',    'slots created by trg_auto_create_vacancy_slot; linked to HC request'
      );
    ELSE
      v_slot_result := public.fn_create_slots_from_hc_request(p_request_id, v_count, v_vcode);
    END IF;
  END IF;

  UPDATE public.headcount_requests
  SET status                  = 'completed',
  vacancy_created             = true,
  slot_created_by_user_id     = v_triggered_by_id,
  slot_created_at             = NOW(),
  created_plantilla_id        = v_first_plantilla_id,
  created_vcode               = v_vcode,
  created_vcodes              = v_vcodes
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'ok',                true,
    'request_id',        p_request_id,
    'headcount_created', v_count,
    'workforce_type',    'stationary',
    'vcode_count',       1,
    'vcodes',            v_vcodes,
    'vacancy_created',   true,
    'reused_vcode',      v_reused_vcode,
    'slot_result',       v_slot_result
  );
END;
$function$;

-- ── 2. _execute_approved_coverage_request ───────────────────────────────────


