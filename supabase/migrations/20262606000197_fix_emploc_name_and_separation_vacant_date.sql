-- Migration: 20262606000196_fix_emploc_name_and_separation_vacant_date.sql
-- Description:
-- 1. Fix _assign_and_deploy_emploc_core: eliminate invalid reference to v_emp.last_name/first_name/middle_name (Bug 3).
-- 2. Fix fn_plantilla_separation_to_vacancy: update coverage vacancy vacant_date to v_sep_date and reset roving vacant_date (Bug 8).

-- ── 1. Update _assign_and_deploy_emploc_core ────────────────────────────────
-- Base: 20262606000193_fix_core_rpc_and_lifecycle_sync.sql
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

  -- Safe name formatting without invalid column references on v_emp
  IF v_app.id IS NOT NULL AND (v_app.last_name IS NOT NULL OR v_app.first_name IS NOT NULL) THEN
    v_formatted_name := public.fn_format_employee_name_full(
      v_app.last_name,
      v_app.first_name,
      v_app.middle_name
    );
  ELSE
    v_formatted_name := COALESCE(NULLIF(trim(v_emp.employee_name_snapshot), ''), NULLIF(trim(v_emp.applicant_name), ''));
  END IF;

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
    status                = 'Moved to Plantilla',
    emploc_no             = v_clean_id,
    moved_to_plantilla_at = NOW(),
    moved_to_plantilla_by = v_actor_profile_id,
    updated_at            = NOW()
  WHERE id = p_hr_emploc_id;

  RETURN v_pl;
END;
$function$;

REVOKE ALL ON FUNCTION public._assign_and_deploy_emploc_core(uuid, text, boolean, text, uuid, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public._assign_and_deploy_emploc_core(uuid, text, boolean, text, uuid, text) TO service_role, authenticated;


-- ── 2. Update fn_plantilla_separation_to_vacancy ────────────────────────────
-- Base: 20262606000193_fix_core_rpc_and_lifecycle_sync.sql
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

  -- ── Coverage / Roving employee path ───────────────────────────────────────
  IF COALESCE(NEW.deployment_type, '') = 'Roving' OR NEW.coverage_slot_id IS NOT NULL OR NEW.coverage_group_id IS NOT NULL THEN

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

      -- Reset vacancy vacant_date to the actual separation date so SLA starts at 0 days
      UPDATE public.vacancies
         SET status               = 'Open',
             is_archived          = false,
             archived_at          = NULL,
             archived_by          = NULL,
             vacant_date          = v_sep_date,
             triggered_by_user_id = v_actor_id,
             triggered_by_name    = v_actor_name,
             updated_at           = NOW()
       WHERE (
         coverage_group_id = COALESCE(NEW.coverage_group_id, (SELECT coverage_group_id FROM public.coverage_slots WHERE id = NEW.coverage_slot_id))
         OR vcode = NEW.vcode
       )
       AND status NOT IN ('Archived', 'Cancelled');

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
                   vacant_date          = v_sep_date,
                   triggered_by_user_id = v_actor_id,
                   triggered_by_name    = v_actor_name,
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
          LEFT JOIN public.stores s ON s.id = v_link.store_id;
        END IF;

        -- Unlink store
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
