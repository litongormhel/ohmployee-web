-- ============================================================================
-- Migration: 20262606000190_allow_add_emploc_in_pending_tab_for_all_authorized_assigners.sql
-- Created: 2026-11-25T15:00:15.000Z
-- Description:
--   Option 2: Allow all authorized Emploc assigners (Super Admin, Head Admin,
--   Encoder, HR Personnel — public.can_assign_pending_hr_emploc()) to assign
--   an Employee Number (+ Add Emploc) directly in both Tab 1 (Pending) and
--   Tab 2 (For Emploc), making document upload in Pending optional rather than
--   a hard blocker for Emploc assignment and deployment to Plantilla.
--
-- Surgical Updates:
--   1. public._assign_and_deploy_emploc_core:
--      - Permits assign_hr_emploc_number from hr_status IN ('Pending', 'For Emploc', 'Complete')
--        for all callers passing can_assign_pending_hr_emploc().
--      - Hardens pool vacancy home account fallback (COALESCE(v_home_acct.account_name, v_emp.account)
--        and COALESCE(v_home_acct.id, v_emp.account_id)) to prevent NOT NULL violation if a pool
--        vacancy's home_account_id is NULL.
--   2. public.list_web_hr_emplocs:
--      - Updates row_capabilities.can_assign_employee_no to allow hr_status IN ('Pending', 'For Emploc')
--        whenever public.can_assign_pending_hr_emploc() is true.
--   3. public.get_web_hr_emploc_detail:
--      - Updates row_capabilities.can_assign_employee_no to allow hr_status IN ('Pending', 'For Emploc')
--        whenever public.can_assign_pending_hr_emploc() is true.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Update public._assign_and_deploy_emploc_core
-- ============================================================================
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
BEGIN
  -- 1. Format validation (rejects empty, spaces, (PENDING), invalid chars)
  IF v_clean_id = '' OR upper(v_clean_id) = '(PENDING)' OR v_clean_id !~ '^[A-Za-z0-9._-]+$' THEN
    RAISE EXCEPTION 'EMPLOYEE_NO_FORMAT_INVALID: Employee number "%" is invalid. Allowed: alphanumeric, dots, underscores, dashes.', v_clean_id
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'EMPLOYEE_NO_FORMAT_INVALID')::text;
  END IF;

  -- 2. Pending deletion lock
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_hr_emploc_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('code', 'ACTION_LOCKED_PENDING_DELETION')::text;
  END IF;

  -- 3. Lock hr_emploc record
  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'RECORD_NOT_FOUND: hr_emploc record % not found or archived', p_hr_emploc_id
      USING ERRCODE = 'P0002', DETAIL = jsonb_build_object('code', 'RECORD_NOT_FOUND')::text;
  END IF;

  -- 3b. Stage gate for Add Emploc (assign_hr_emploc_number):
  -- Option 2: All authorized Emploc assigners (SA, HA, Encoder, HR Personnel) may assign from Pending, For Emploc, or Complete.
  IF p_source_fn = 'assign_hr_emploc_number' THEN
    IF v_emp.hr_status NOT IN ('Pending', 'For Emploc', 'Complete') AND v_emp.status <> 'Moved to Plantilla' THEN
      RAISE EXCEPTION 'INVALID_STATE_FOR_ASSIGN: Cannot assign Employee ID from hr_status "%". Expected "Pending" or "For Emploc".', v_emp.hr_status
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STATE_FOR_ASSIGN')::text;
    END IF;
  END IF;

  -- Safe idempotent no-op check: already moved with same number
  IF v_emp.status = 'Moved to Plantilla' AND v_emp.employee_no = v_clean_id THEN
    SELECT * INTO v_existing_pl
    FROM public.plantilla
    WHERE hr_emploc_id = p_hr_emploc_id
      AND COALESCE(is_deleted, false) = false
    LIMIT 1;
    IF FOUND THEN
      RETURN v_existing_pl;
    END IF;
  END IF;

  -- Fetch structured applicant data
  IF v_emp.applicant_id IS NOT NULL THEN
    SELECT * INTO v_app FROM public.applicants WHERE id = v_emp.applicant_id;
  END IF;

  -- 4. REQUIRED PLANTILLA FIELDS VALIDATION (NO SILENT DEFAULTS)
  IF v_emp.hired_date IS NULL THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: hired_date is required before deployment to Plantilla'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'hired_date')::text;
  END IF;

  IF (v_app.first_name IS NULL OR btrim(v_app.first_name) = '') OR
     (v_app.last_name IS NULL OR btrim(v_app.last_name) = '') THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: applicant first_name and last_name are required'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'applicant_name')::text;
  END IF;

  IF v_emp.account_id IS NULL AND (v_emp.account IS NULL OR btrim(v_emp.account) = '') THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: account is required'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'account')::text;
  END IF;

  IF v_emp.position IS NULL OR btrim(v_emp.position) = '' THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: position is required'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'position')::text;
  END IF;

  -- 6. SLOT SELECTION AND RESERVATION (Stationary non-pool non-roving)
  IF v_emp.vacancy_id IS NOT NULL THEN
    SELECT v.is_pool_vacancy, v.pool_type_id, v.home_account_id
      INTO v_is_pool, v_pool_type_id, v_home_account_id
      FROM vacancies v
     WHERE v.id = v_emp.vacancy_id;
  END IF;
  v_is_pool := COALESCE(v_is_pool, false);

  IF NOT v_is_pool AND COALESCE(v_emp.assignment_type::text, 'Stationary') NOT IN ('Roving', 'Coverage') AND v_emp.coverage_slot_id IS NULL THEN
    IF v_emp.store_id IS NULL AND (v_emp.store_name IS NULL OR btrim(v_emp.store_name) = '') THEN
      RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: store is required for stationary deployment'
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'store')::text;
    END IF;
    IF v_emp.store_id IS NULL THEN
      RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: store_id is required for stationary deployment'
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'store_id')::text;
    END IF;
  END IF;

  -- Resolve canonical formatted name and normalized name
  v_formatted_name := v_app.last_name || ', ' || v_app.first_name || COALESCE(' ' || NULLIF(btrim(v_app.middle_name), ''), '');
  v_norm_name      := public.fn_normalize_person_name(v_app.first_name, v_app.middle_name, v_app.last_name, NULL, NULL);

  -- 5. REGISTRY RACE-SAFE CHECK UNDER FOR UPDATE LOCK
  SELECT * INTO v_reg
  FROM public.employee_number_registry
  WHERE emploc_no = v_clean_id
  FOR UPDATE;

  IF FOUND THEN
    IF v_reg.status IN ('assigned', 'rehire_reused') THEN
      v_match := public.fn_match_person_name(v_reg.normalized_name, v_norm_name);

      IF (v_match->>'match')::boolean = false THEN
        RAISE EXCEPTION 'EMPLOYEE_NO_ALREADY_ASSIGNED: Employee number % is permanently registered to %',
          v_clean_id, v_reg.display_name
          USING ERRCODE = '23505',
                DETAIL = jsonb_build_object(
                  'code', 'EMPLOYEE_NO_ALREADY_ASSIGNED',
                  'employee_no', v_clean_id,
                  'registered_to', v_reg.display_name,
                  'registered_norm', v_reg.normalized_name,
                  'incoming_name', v_formatted_name,
                  'reason', v_match->>'reason'
                )::text;
      END IF;

      IF EXISTS (
        SELECT 1 FROM public.plantilla p
        WHERE (p.employee_no = v_clean_id OR p.emploc_no = v_clean_id)
          AND p.status IN ('Active', 'On Leave', 'For Deactivation', 'Pending Deactivation')
          AND COALESCE(p.is_deleted, false) = false
          AND (p.hr_emploc_id IS NULL OR p.hr_emploc_id <> p_hr_emploc_id)
      ) OR EXISTS (
        SELECT 1 FROM public.hr_emploc h
        WHERE (h.employee_no = v_clean_id OR h.emploc_no = v_clean_id)
          AND h.status NOT IN ('Backout', 'Moved to Plantilla')
          AND h.id <> p_hr_emploc_id
          AND h.deleted_at IS NULL
      ) THEN
        RAISE EXCEPTION 'EMPLOYEE_ALREADY_ACTIVE: % already has an active placement or active Plantilla record with number %',
          v_formatted_name, v_clean_id
          USING ERRCODE = '23505',
                DETAIL = jsonb_build_object(
                  'code', 'EMPLOYEE_ALREADY_ACTIVE',
                  'employee_no', v_clean_id,
                  'person', v_formatted_name
                )::text;
      END IF;

      IF (v_match->>'type') = 'WARNING_MISSING_MIDDLE' THEN
        IF NOT p_confirm_reuse OR coalesce(btrim(p_reuse_reason), '') = '' THEN
          RAISE EXCEPTION 'MIDDLE_NAME_CONFIRM_REQUIRED: % matches % on first and last name, but one record is missing a middle name. Confirm with reason.',
            v_formatted_name, v_reg.display_name
            USING ERRCODE = '23505',
                  DETAIL = jsonb_build_object(
                    'code', 'MIDDLE_NAME_CONFIRM_REQUIRED',
                    'employee_no', v_clean_id,
                    'registered_to', v_reg.display_name,
                    'incoming_name', v_formatted_name,
                    'reason', v_match->>'reason'
                  )::text;
        END IF;
      END IF;

      IF v_reg.source_hr_emploc_id IS DISTINCT FROM p_hr_emploc_id THEN
        IF NOT p_confirm_reuse OR coalesce(btrim(p_reuse_reason), '') = '' THEN
          RAISE EXCEPTION 'REHIRE_CONFIRM_REQUIRED: % was previously assigned number %. Confirm rehire reuse with reason.',
            v_formatted_name, v_clean_id
            USING ERRCODE = '23505',
                  DETAIL = jsonb_build_object(
                    'code', 'REHIRE_CONFIRM_REQUIRED',
                    'employee_no', v_clean_id,
                    'display_name', v_reg.display_name,
                    'first_assigned_at', v_reg.first_assigned_at,
                    'status', v_reg.status
                  )::text;
        END IF;
        v_is_rehire := true;
      END IF;
    END IF;
  END IF;

  FOR r_cand IN (
    SELECT *
    FROM public.employee_number_registry reg
    WHERE reg.emploc_no <> v_clean_id
      AND reg.status IN ('assigned', 'rehire_reused')
      AND (
        split_part(reg.normalized_name, '|', 1) = split_part(v_norm_name, '|', 1)
        OR (split_part(reg.normalized_name, '|', 1) IN ('HAUTEA', 'HUATEA') AND split_part(v_norm_name, '|', 1) IN ('HAUTEA', 'HUATEA'))
        OR EXISTS (
          SELECT 1 FROM public.registry_name_aliases rna
          WHERE rna.normalized_name = reg.normalized_name OR rna.alias_normalized_name = reg.normalized_name
        )
      )
  ) LOOP
    v_dup_match := public.fn_match_person_name(r_cand.normalized_name, v_norm_name);
    IF (v_dup_match->>'match')::boolean = true THEN
      IF (v_dup_match->>'type') <> 'WARNING_MISSING_MIDDLE' AND (
        EXISTS (
          SELECT 1 FROM public.plantilla p
          WHERE (p.employee_no = r_cand.emploc_no OR p.emploc_no = r_cand.emploc_no)
            AND p.status IN ('Active', 'On Leave', 'For Deactivation', 'Pending Deactivation')
            AND COALESCE(p.is_deleted, false) = false
            AND (p.hr_emploc_id IS NULL OR p.hr_emploc_id <> p_hr_emploc_id)
        ) OR EXISTS (
          SELECT 1 FROM public.hr_emploc h
          WHERE (h.employee_no = r_cand.emploc_no OR h.emploc_no = r_cand.emploc_no)
            AND h.status NOT IN ('Backout', 'Moved to Plantilla')
            AND h.id <> p_hr_emploc_id
            AND h.deleted_at IS NULL
        )
      ) THEN
        RAISE EXCEPTION 'EMPLOYEE_ALREADY_ACTIVE: % already has an active placement or active Plantilla record under Employee number %',
          v_formatted_name, r_cand.emploc_no
          USING ERRCODE = '23505',
                DETAIL = jsonb_build_object(
                  'code', 'EMPLOYEE_ALREADY_ACTIVE',
                  'employee_no', r_cand.emploc_no,
                  'person', v_formatted_name
                )::text;
      END IF;

      IF NOT p_confirm_reuse OR coalesce(btrim(p_reuse_reason), '') = '' THEN
        IF (v_dup_match->>'type') = 'WARNING_MISSING_MIDDLE' THEN
          RAISE EXCEPTION 'MIDDLE_NAME_CONFIRM_REQUIRED (POSSIBLE_DUPLICATE_PERSON): % matches % (Employee number %) on first and last name with one side missing middle name. Confirm with reason.',
            v_formatted_name, r_cand.display_name, r_cand.emploc_no
            USING ERRCODE = '23505',
                  DETAIL = jsonb_build_object(
                    'code', 'MIDDLE_NAME_CONFIRM_REQUIRED',
                    'secondary_code', 'POSSIBLE_DUPLICATE_PERSON',
                    'new_employee_no', v_clean_id,
                    'existing_employee_no', r_cand.emploc_no,
                    'display_name', r_cand.display_name
                  )::text;
        ELSE
          RAISE EXCEPTION 'POSSIBLE_DUPLICATE_PERSON: % is already registered with Employee number %. Confirm duplicate assignment with reason.',
            v_formatted_name, r_cand.emploc_no
            USING ERRCODE = '23505',
                  DETAIL = jsonb_build_object(
                    'code', 'POSSIBLE_DUPLICATE_PERSON',
                    'new_employee_no', v_clean_id,
                    'existing_employee_no', r_cand.emploc_no,
                    'display_name', r_cand.display_name,
                    'match_type', v_dup_match->>'type'
                  )::text;
        END IF;
      END IF;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM public.hr_emploc h
    LEFT JOIN public.applicants a ON a.id = h.applicant_id
    WHERE h.id <> p_hr_emploc_id
      AND h.deleted_at IS NULL
      AND h.status NOT IN ('Backout', 'Moved to Plantilla')
      AND h.employee_no IS NOT NULL AND btrim(h.employee_no) <> ''
      AND (public.fn_match_person_name(
            public.fn_normalize_person_name(a.first_name, a.middle_name, a.last_name, NULL, coalesce(h.employee_name_snapshot, h.applicant_name)),
            v_norm_name
          )->>'match')::boolean = true
      AND (public.fn_match_person_name(
            public.fn_normalize_person_name(a.first_name, a.middle_name, a.last_name, NULL, coalesce(h.employee_name_snapshot, h.applicant_name)),
            v_norm_name
          )->>'type') <> 'WARNING_MISSING_MIDDLE'
  ) THEN
    RAISE EXCEPTION 'EMPLOYEE_ALREADY_ACTIVE: % already has an active hr_emploc record',
      v_formatted_name
      USING ERRCODE = '23505',
            DETAIL = jsonb_build_object(
              'code', 'EMPLOYEE_ALREADY_ACTIVE',
              'person', v_formatted_name
            )::text;
  END IF;

  IF NOT v_is_pool AND COALESCE(v_emp.assignment_type::text, 'Stationary') NOT IN ('Roving', 'Coverage') AND v_emp.coverage_slot_id IS NULL THEN
    IF v_emp.slot_id IS NOT NULL THEN
      SELECT id INTO v_slot_id
      FROM public.plantilla_slots
      WHERE id = v_emp.slot_id
        AND slot_status IN ('open', 'hr_processing')
      FOR UPDATE SKIP LOCKED;
    END IF;

    IF v_slot_id IS NULL THEN
      SELECT id INTO v_slot_id
      FROM public.plantilla_slots
      WHERE legacy_vcode = v_emp.vcode
        AND slot_status = 'open'
      ORDER BY created_at ASC
      LIMIT 1
      FOR UPDATE SKIP LOCKED;
    END IF;

    IF v_slot_id IS NULL THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE: No available headcount slot for VCode %', v_emp.vcode
        USING ERRCODE = '22023',
              DETAIL = jsonb_build_object('code', 'SLOT_UNAVAILABLE', 'vcode', v_emp.vcode)::text;
    END IF;

    v_slot_auth := public.fn_set_slot_status(
      p_slot_id      => v_slot_id,
      p_new_status   => 'hr_processing',
      p_reason_code  => NULL,
      p_performed_by => v_actor_profile_id,
      p_remarks      => 'auto_move_to_plantilla: reserved for hr_emploc ' || p_hr_emploc_id::text
    );
    IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE: Slot % reservation blocked: %',
        v_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
        USING ERRCODE = '22023',
              DETAIL = jsonb_build_object('code', 'SLOT_UNAVAILABLE', 'slot_id', v_slot_id, 'blocked_reason', v_slot_auth->>'blocked_reason')::text;
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
      COALESCE(v_home_acct.account_name, v_emp.account), COALESCE(v_home_acct.id, v_emp.account_id),
      NULL, NULL,
      v_emp.position,           v_emp.position_id_snapshot,
      v_clean_id,               v_clean_id,
      v_formatted_name,         v_formatted_name,
      v_app.first_name,         v_app.middle_name,       v_app.last_name,
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
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

  ELSIF v_emp.coverage_slot_id IS NOT NULL OR COALESCE(v_emp.assignment_type::text, 'Stationary') = 'Coverage' THEN
    -- Coverage Group deployment path (respects plantilla_roving_coverage_mutex_chk: roving_assignment_id IS NULL)
    INSERT INTO plantilla (
      account,              account_id,           chain_id,             province_id,
      store_id,             store_name,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,          last_name,
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
      v_emp.store_id, v_emp.store_name,
      v_emp.position, v_emp.position_id_snapshot,
      v_clean_id, v_clean_id,
      v_formatted_name, v_formatted_name,
      v_app.first_name, v_app.middle_name, v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot, v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date, v_emp.vacancy_id, v_emp.vacancy_code_snapshot,
      COALESCE(v_emp.vcode, v_emp.vacancy_code_snapshot),
      v_emp.hrco_name, v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      v_emp.coverage_slot_id, v_emp.coverage_group_id,
      'Roving',
      'Active', CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    -- Link all currently Confirmed stores from hr_emploc_store_links into plantilla_store_links
    FOR r_link IN
      SELECT hsl.id, hsl.store_id, hsl.vacancy_id, COALESCE(hsl.vcode, s.vcode) AS resolved_vcode,
             COALESCE(hsl.store_name, s.store_name) AS resolved_store_name
        FROM public.hr_emploc_store_links hsl
        LEFT JOIN public.stores s ON s.id = hsl.store_id
       WHERE hsl.hr_emploc_id = v_emp.id
         AND hsl.status = 'Confirmed'
         AND hsl.deleted_at IS NULL
    LOOP
      IF r_link.resolved_vcode IS NOT NULL THEN
        INSERT INTO public.plantilla_store_links (
          plantilla_id, coverage_group_id, hr_emploc_store_link_id,
          vacancy_id, vcode, store_name, account,
          status, linked_at, linked_by, created_by, updated_by
        ) VALUES (
          v_pl.id, v_emp.coverage_group_id, r_link.id,
          r_link.vacancy_id, r_link.resolved_vcode, r_link.resolved_store_name, v_emp.account,
          'Active', NOW(), v_actor_profile_id, v_actor_profile_id, v_actor_profile_id
        )
        ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL)
        DO UPDATE SET
          coverage_group_id = COALESCE(public.plantilla_store_links.coverage_group_id, EXCLUDED.coverage_group_id),
          status            = 'Active',
          updated_at        = NOW(),
          updated_by        = v_actor_profile_id;

        UPDATE public.plantilla_slots
           SET slot_status                   = 'occupied',
               current_occupant_plantilla_id = v_pl.id,
               updated_at                    = NOW(),
               updated_by                    = v_actor_profile_id
         WHERE legacy_vcode = r_link.resolved_vcode
           AND closed_at IS NULL
           AND slot_status IN ('open', 'pipeline', 'hr_processing');

        UPDATE public.vacancies
           SET status     = 'Filled',
               updated_at = NOW(),
               updated_by = v_actor_profile_id
         WHERE vcode = r_link.resolved_vcode
           AND deleted_at IS NULL
           AND status NOT IN ('Filled', 'Closed', 'Archived');
      END IF;
    END LOOP;

    IF v_emp.coverage_slot_id IS NOT NULL THEN
      PERFORM public.fn_sync_coverage_slot_to_active(
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
      v_clean_id,           v_clean_id,
      v_formatted_name,     v_formatted_name,
      v_app.first_name,     v_app.middle_name,      v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot,   v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date,     v_emp.vacancy_id,        v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name,      v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      'Active',             CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id, NOW(), NOW()
    )
    RETURNING * INTO v_pl;
  END IF;

  -- 8. FINALIZE SLOT AS 'occupied' (RECONCILED VALUE)
  IF v_slot_id IS NOT NULL THEN
    v_slot_auth := public.fn_set_slot_status(
      p_slot_id               => v_slot_id,
      p_new_status            => 'occupied',
      p_reason_code           => NULL,
      p_performed_by          => v_actor_profile_id,
      p_remarks               => 'auto_move_to_plantilla: slot occupied by plantilla ' || v_pl.id::text,
      p_occupant_plantilla_id => v_pl.id
    );
    IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE: Slot % occupancy blocked: %',
        v_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
        USING ERRCODE = '22023',
              DETAIL = jsonb_build_object('code', 'SLOT_UNAVAILABLE', 'slot_id', v_slot_id, 'blocked_reason', v_slot_auth->>'blocked_reason')::text;
    END IF;
  END IF;

  -- 9. VACANCY CLOSURE (if all slots filled)
  IF NOT v_is_pool AND COALESCE(v_emp.assignment_type::text, 'Stationary') NOT IN ('Roving', 'Coverage') AND v_emp.coverage_slot_id IS NULL THEN
    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE public.vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor_profile_id
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
           updated_by = v_actor_profile_id
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

  -- 10. STAMP REGISTRY BEFORE HR_EMPLOC UPDATE (so trigger sees registered entry)
  INSERT INTO public.employee_number_registry (
    emploc_no, normalized_name, display_name, status,
    first_assigned_at, first_assigned_by, last_assigned_at, last_assigned_by,
    source_hr_emploc_id, source_plantilla_id,
    history
  ) VALUES (
    v_clean_id, v_norm_name, v_formatted_name,
    CASE WHEN v_is_rehire THEN 'rehire_reused' ELSE 'assigned' END,
    NOW(), v_actor_profile_id, NOW(), v_actor_profile_id,
    p_hr_emploc_id, v_pl.id,
    jsonb_build_array(
      jsonb_build_object(
        'action', CASE WHEN v_is_rehire THEN 'rehire_reuse' ELSE 'initial_assignment' END,
        'actor', v_actor_profile_id,
        'timestamp', now(),
        'source', p_source_fn,
        'reuse_reason', p_reuse_reason
      )
    )
  )
  ON CONFLICT (emploc_no) DO UPDATE SET
    normalized_name     = EXCLUDED.normalized_name,
    display_name        = EXCLUDED.display_name,
    status              = EXCLUDED.status,
    last_assigned_at    = NOW(),
    last_assigned_by    = v_actor_profile_id,
    source_hr_emploc_id = p_hr_emploc_id,
    source_plantilla_id = v_pl.id,
    history             = public.employee_number_registry.history || EXCLUDED.history;

  -- 11. UPDATE HR_EMPLOC STATUS (Final: Moved to Plantilla / Transferred)
  UPDATE public.hr_emploc
     SET employee_no           = v_clean_id,
         emploc_no             = v_clean_id,
         status                = 'Moved to Plantilla',
         hr_status             = 'Transferred',
         moved_to_plantilla_at = NOW(),
         moved_to_plantilla_by = v_actor_profile_id,
         updated_at            = NOW(),
         updated_by            = v_actor_profile_id
   WHERE id = p_hr_emploc_id;

  -- 11b. ENQUEUE 3-DAY DOCUMENT PURGE (never rolls back deployment on error)
  BEGIN
    PERFORM public.enqueue_hr_emploc_docs_cleanup(p_hr_emploc_id, 'deployed_3day_ttl', interval '3 days');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- 12. SINGLE AUDIT / TIMELINE LOG ENTRY
  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    to_jsonb(v_emp),
    jsonb_build_object(
      'action', 'assign_and_move_to_plantilla',
      'employee_no', v_clean_id,
      'plantilla_id', v_pl.id,
      'actor_name', v_actor_name,
      'actor_id', v_actor_profile_id,
      'source', p_source_fn,
      'log_message', format('Assigned Employee ID %s and automatically moved to Plantilla (Slot %s) by %s', v_clean_id, coalesce(v_slot_id::text, v_emp.coverage_slot_id::text, 'Pool/Roving'), v_actor_name)
    )
  );

  RETURN v_pl;
END;
$function$;


-- ============================================================================
-- 2. Update public.list_web_hr_emplocs
-- ============================================================================
DROP FUNCTION IF EXISTS public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text);
DROP FUNCTION IF EXISTS public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text, integer);
DROP FUNCTION IF EXISTS public.list_web_hr_emplocs;

CREATE OR REPLACE FUNCTION public.list_web_hr_emplocs(
  p_queue                text    DEFAULT NULL::text,
  p_status               text    DEFAULT NULL::text,
  p_deficiency           text    DEFAULT NULL::text,
  p_sla_filter           text    DEFAULT NULL::text,
  p_account_id           uuid    DEFAULT NULL::uuid,
  p_group_id             uuid    DEFAULT NULL::uuid,
  p_search               text    DEFAULT NULL::text,
  p_limit                integer DEFAULT 50,
  p_offset               integer DEFAULT 0,
  p_sort_by              text    DEFAULT 'date_requested'::text,
  p_sort_dir             text    DEFAULT 'desc'::text,
  p_deployed_window_days integer DEFAULT NULL::integer
)
RETURNS TABLE(
  hr_emploc_id         uuid,
  applicant_name       text,
  vcode                text,
  account_id           uuid,
  account_name         text,
  group_id             uuid,
  group_name           text,
  store_id             uuid,
  store_name           text,
  position_title       text,
  hr_status            text,
  status               text,
  emploc_no            text,
  employee_no          text,
  date_requested       timestamp with time zone,
  created_at           timestamp with time zone,
  hired_date           date,
  assignment_type      text,
  roving_assignment_id uuid,
  aging_days           integer,
  sla_breached         boolean,
  sla_status           text,
  sla_deadline         timestamp with time zone,
  deficiency_summary   jsonb,
  is_pending_deletion  boolean,
  row_capabilities     jsonb,
  total_count          bigint
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
  v_sort_by      text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'date_requested'));
  v_sort_dir     text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'desc'));
  v_limit        integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset       integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc list requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, COALESCE(public.get_my_role(), r.role_name), COALESCE(public.get_my_role_level(), r.role_level)
  INTO   v_profile_id, v_role_name, v_role_level
  FROM   public.users_profile up
  JOIN   public.roles r ON r.id = up.role_id
  WHERE  up.auth_user_id = v_auth_uid
    AND  up.is_active = TRUE
    AND  up.archived_at IS NULL
  ORDER  BY up.created_at DESC
  LIMIT  1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF v_sort_by <> ALL (ARRAY[
    'vcode',
    'applicant_name',
    'account_name',
    'group_name',
    'store_name',
    'position_title',
    'hr_status',
    'status',
    'emploc_no',
    'employee_no',
    'date_requested',
    'created_at',
    'aging_days'
  ]) THEN
    RAISE EXCEPTION 'invalid sort field: %', p_sort_by
      USING ERRCODE = '22023';
  END IF;

  IF v_sort_dir <> ALL (ARRAY['asc', 'desc']) THEN
    RAISE EXCEPTION 'invalid sort direction: %', p_sort_dir
      USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      h.id AS hr_emploc_id,
      h.applicant_name,
      h.vcode,
      h.account_id,
      a.account_name,
      a.group_id,
      g.group_name,
      h.store_id,
      h.store_name,
      h.position AS position_title,
      COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)) AS hrco_name,
      h.hr_status,
      h.status,
      h.emploc_no,
      h.employee_no,
      h.date_requested,
      h.created_at,
      h.hired_date,
      h.assignment_type::text AS assignment_type,
      h.roving_assignment_id,
      h.correction_reason,
      h.deleted_at,
      
      -- SLA & Aging computation
      GREATEST(0, (EXTRACT(day FROM (now() - COALESCE(h.date_requested, h.created_at))))::integer) AS aging_days,
      
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))) AS sla_breached,
      
      CASE
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))
          THEN 'breached'
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval))
          THEN 'warning'
        ELSE 'normal'
      END AS sla_status,
      
      (COALESCE(h.date_requested, h.created_at) + INTERVAL '3 days') AS sla_deadline,
      
      -- Deficiency Summary
      CASE
        WHEN h.correction_reason IS NULL THEN jsonb_build_object('active_count', 0, 'issues', '[]'::jsonb)
        ELSE jsonb_build_object(
          'active_count', CASE WHEN jsonb_typeof(h.correction_reason) = 'array' THEN jsonb_array_length(h.correction_reason) ELSE 1 END,
          'issues', CASE
            WHEN jsonb_typeof(h.correction_reason) = 'array' THEN (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'code', el->>'code',
                  'comment', el->>'comment',
                  'label', COALESCE((SELECT it.label FROM public.hr_emploc_issue_types it WHERE it.code = el->>'code'), el->>'code')
                )
              )
              FROM jsonb_array_elements(h.correction_reason) el
            )
            ELSE jsonb_build_array(
              jsonb_build_object(
                'code', h.correction_reason->>'type',
                'comment', h.correction_reason->>'comment',
                'label', COALESCE((SELECT it.label FROM public.hr_emploc_issue_types it WHERE it.code = h.correction_reason->>'type'), h.correction_reason->>'type')
              )
            )
          END
        )
      END AS deficiency_summary,
      
      -- Deletion Overlay visibility
      EXISTS (
        SELECT 1 FROM public.hr_emploc_deletion_requests dr
        WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
      ) AS is_pending_deletion,
      
      -- UI capabilities presentation hints
      jsonb_build_object(
        'can_view_detail', true,
        'hrco_name', COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)),
        'remarks', COALESCE(h.ops_remarks, h.hr_remarks),
        'ops_remarks', h.ops_remarks,
        'hr_remarks', h.hr_remarks,
        'attachment_url', CASE
          WHEN ((h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') AND NOT public.is_super_admin()) OR NOT public.can_view_hr_emploc_docs(h.id) THEN NULL
          ELSE (
            SELECT ca.storage_path
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
            ORDER BY ca.uploaded_at DESC
            LIMIT 1
          )
        END,
        'attachment_file_name', CASE
          WHEN ((h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') AND NOT public.is_super_admin()) OR NOT public.can_view_hr_emploc_docs(h.id) THEN NULL
          ELSE (
            SELECT ca.original_filename
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
            ORDER BY ca.uploaded_at DESC
            LIMIT 1
          )
        END,
        'doc_count', CASE
          WHEN (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') AND NOT public.is_super_admin() THEN 0
          ELSE (
            SELECT count(*)::int
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
          )
        END,
        'attachments', CASE
          WHEN ((h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') AND NOT public.is_super_admin()) OR NOT public.can_view_hr_emploc_docs(h.id) THEN '[]'::jsonb
          ELSE COALESCE((
            SELECT jsonb_agg(
              jsonb_build_object(
                'id', ca.id,
                'original_filename', ca.original_filename,
                'mime_type', ca.mime_type,
                'size_bytes', ca.size_bytes,
                'stage', ca.stage,
                'storage_path', ca.storage_path,
                'object_path', regexp_replace(ca.storage_path, '^hr-corrections/', ''),
                'uploaded_by', ca.uploaded_by,
                'uploaded_at', ca.uploaded_at,
                'created_at', ca.created_at,
                'can_remove', (
                  public.can_upload_hr_emploc_docs(h.id)
                  AND (public.is_super_admin() OR ca.uploaded_by = v_profile_id)
                )
              ) ORDER BY ca.uploaded_at DESC
            )
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
          ), '[]'::jsonb)
        END,
        'can_upload_docs', public.can_upload_hr_emploc_docs(h.id),
        'can_submit_requirements', (
          public.can_upload_hr_emploc_docs(h.id)
          AND h.hr_status = 'Pending'
        ),
        'can_view_docs', public.can_view_hr_emploc_docs(h.id),
        'can_edit_emploc', (
          public.can_edit_deployed_hr_emploc()
          AND (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred')
        ),
        'can_revert_to_pending', (
          public.can_edit_deployed_hr_emploc()
          AND (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred')
        ),
        'can_request_deletion', (
          h.status <> 'Moved to Plantilla'
          AND h.hr_status <> 'Pending Deletion'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
          AND (v_role_level >= 70 OR v_role_name IN ('OM', 'HRCO', 'ATL', 'TL', 'ATL/TL') OR public.i_am_ops() OR public.i_have_full_access())
        ),
        'can_withdraw_deletion_request', (
          EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
          AND (
            public.i_have_full_access()
            OR EXISTS (
              SELECT 1 FROM public.hr_emploc_deletion_requests dr
              WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending' AND dr.requested_by_user_id = v_profile_id
            )
          )
        ),
        'can_review_deletion', (
          (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
          AND EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_approve_correction', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Review'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_revert_correction', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Review'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_review_correction', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Review'
          AND NOT EXISTS (
            SELECT 1
            FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id
              AND dr.status = 'Pending'
          )
        ),
        'can_submit_correction', (
          public.can_upload_hr_emploc_docs(h.id)
          AND h.hr_status = 'For Correction'
        ),
        'can_move_to_plantilla', false,
        'can_tag_deficiency', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Emploc'
          AND h.status <> 'Moved to Plantilla'
          AND NOT EXISTS (
            SELECT 1
            FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id
              AND dr.status = 'Pending'
          )
        ),
        'can_assign_employee_no', (
          public.can_assign_pending_hr_emploc()
          AND COALESCE(h.employee_no, '') = ''
          AND h.status <> 'Moved to Plantilla'
          AND h.hr_status IN ('Pending', 'For Emploc')
          AND NOT EXISTS (
            SELECT 1
            FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id
              AND dr.status = 'Pending'
          )
        )
      ) AS row_capabilities
    FROM public.hr_emploc h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    LEFT JOIN public.groups g ON g.id = a.group_id
    WHERE
      h.deleted_at IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.account = ANY (public.get_my_allowed_accounts())
          OR
          EXISTS (
            SELECT 1 FROM public.user_scopes us
            WHERE us.user_id = v_profile_id AND us.account_id = h.account_id
          )
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = h.account_id
            WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
          )
          OR EXISTS (
            SELECT 1 FROM public.users_profile up_fallback JOIN public.accounts ac ON ac.id = h.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
              AND (up_fallback.account_id = h.account_id OR up_fallback.group_id = ac.group_id)
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      -- Queue Filter (including 'for_emploc', 'deployed', etc.)
      (p_queue IS NULL
       OR (p_queue = 'pending' AND s.hr_status = 'Pending' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue = 'for_emploc' AND s.hr_status = 'For Emploc' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue = 'correction' AND s.hr_status = 'For Correction' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue = 'review' AND s.hr_status = 'For Review' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue IN ('deployed', 'transferred') AND (
            s.status = 'Moved to Plantilla'
            OR s.hr_status = 'Transferred'
          )
          AND s.status <> 'Backout'
          AND s.deleted_at IS NULL
          AND (
            p_deployed_window_days IS NULL
            OR COALESCE(s.hired_date::timestamp with time zone, s.date_requested, s.created_at) >= (now() - (p_deployed_window_days || ' days')::interval)
          )
       )
       OR (p_queue = 'rejected' AND s.hr_status = 'Rejected' AND s.deleted_at IS NULL)
      )
      AND (p_deficiency IS NULL
       OR (p_deficiency = 'any' AND s.deficiency_summary->'active_count' > '0'::jsonb)
       OR (p_deficiency = 'none' AND s.deficiency_summary->'active_count' = '0'::jsonb)
       OR (
         s.deficiency_summary->'active_count' > '0'::jsonb AND EXISTS (
           SELECT 1 FROM jsonb_array_elements(s.deficiency_summary->'issues') el
           WHERE el->>'code' = p_deficiency
         )
       )
      )
      AND (p_sla_filter IS NULL OR s.sla_status = p_sla_filter)
      AND (p_status IS NULL OR s.status = p_status)
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.applicant_name ILIKE '%' || btrim(p_search) || '%'
        OR s.employee_no ILIKE '%' || btrim(p_search) || '%'
        OR s.emploc_no ILIKE '%' || btrim(p_search) || '%'
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
        OR s.hrco_name ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT f.*, count(*) OVER () AS total_count
    FROM filtered f
  )
  SELECT
    c.hr_emploc_id,
    c.applicant_name,
    c.vcode,
    c.account_id,
    c.account_name,
    c.group_id,
    c.group_name,
    c.store_id,
    c.store_name,
    c.position_title,
    c.hr_status,
    c.status,
    c.emploc_no,
    c.employee_no,
    c.date_requested,
    c.created_at,
    c.hired_date,
    c.assignment_type,
    c.roving_assignment_id,
    c.aging_days,
    c.sla_breached,
    c.sla_status,
    c.sla_deadline,
    c.deficiency_summary,
    c.is_pending_deletion,
    c.row_capabilities,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vcode'            THEN c.vcode END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vcode'            THEN c.vcode END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'applicant_name'   THEN c.applicant_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'applicant_name'   THEN c.applicant_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'account_name'     THEN c.account_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name'     THEN c.account_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'group_name'       THEN c.group_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name'       THEN c.group_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'store_name'       THEN c.store_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name'       THEN c.store_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'position_title'   THEN c.position_title END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'position_title'   THEN c.position_title END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'hr_status'        THEN c.hr_status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'hr_status'        THEN c.hr_status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'status'           THEN c.status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'status'           THEN c.status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'emploc_no'        THEN c.emploc_no END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'emploc_no'        THEN c.emploc_no END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'employee_no'      THEN c.employee_no END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'employee_no'      THEN c.employee_no END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'date_requested'   THEN c.date_requested END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'date_requested'   THEN c.date_requested END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'created_at'       THEN c.created_at END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'created_at'       THEN c.created_at END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'aging_days'       THEN c.aging_days END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'aging_days'       THEN c.aging_days END DESC NULLS LAST,
    c.created_at DESC NULLS LAST
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text, integer) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text, integer) TO authenticated, service_role;


-- ============================================================================
-- 3. Update public.get_web_hr_emploc_detail
-- ============================================================================
DROP FUNCTION IF EXISTS public.get_web_hr_emploc_detail(uuid);
DROP FUNCTION IF EXISTS public.get_web_hr_emploc_detail;

CREATE OR REPLACE FUNCTION public.get_web_hr_emploc_detail(p_hr_emploc_id uuid)
RETURNS TABLE(
  hr_emploc_id              uuid,
  applicant_name            text,
  vcode                     text,
  vacancy_id                uuid,
  vacancy_code_snapshot     text,
  position_id_snapshot      uuid,
  position_title            text,
  assignment_type           text,
  roving_assignment_id      uuid,
  covered_stores            jsonb,
  account_id                uuid,
  account_name              text,
  group_id                  uuid,
  group_name                text,
  store_id                  uuid,
  store_name                text,
  hr_status                 text,
  status                    text,
  emploc_no                 text,
  employee_no               text,
  date_requested            timestamp with time zone,
  created_at                timestamp with time zone,
  hired_date                date,
  deployed_by_user_id       uuid,
  hrco_user_id_snapshot     uuid,
  hrco_name                 text,
  employee_lookup_found     boolean,
  employee_lookup_synced_at timestamp with time zone,
  employee_lookup_remarks   text,
  employee_name_snapshot    text,
  birthdate_snapshot        date,
  civil_status_snapshot     text,
  requirement_overall_status text,
  ops_remarks               text,
  hr_remarks                text,
  hr_rejection_reason       text,
  hr_reviewed_by            text,
  hr_reviewed_at            timestamp with time zone,
  deficiency_summary        jsonb,
  correction_reason         jsonb,
  correction_attachments    jsonb,
  deletion_request          jsonb,
  sla_breached              boolean,
  sla_status                text,
  sla_deadline              timestamp with time zone,
  aging_days                integer,
  timeline                  jsonb,
  row_capabilities          jsonb
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc detail requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, COALESCE(public.get_my_role(), r.role_name), COALESCE(public.get_my_role_level(), r.role_level)
  INTO   v_profile_id, v_role_name, v_role_level
  FROM   public.users_profile up
  JOIN   public.roles r ON r.id = up.role_id
  WHERE  up.auth_user_id = v_auth_uid
    AND  up.is_active = TRUE
    AND  up.archived_at IS NULL
  ORDER  BY up.created_at DESC
  LIMIT  1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  -- Validate record existence and scoped visibility
  IF NOT EXISTS (
    SELECT 1 FROM public.hr_emploc h
    WHERE h.id = p_hr_emploc_id
      AND h.deleted_at IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.account = ANY (public.get_my_allowed_accounts())
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us
            WHERE us.user_id = v_profile_id AND us.account_id = h.account_id
          )
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = h.account_id
            WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
          )
          OR EXISTS (
            SELECT 1 FROM public.users_profile up_fallback JOIN public.accounts ac ON ac.id = h.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
              AND (up_fallback.account_id = h.account_id OR up_fallback.group_id = ac.group_id)
          )
        )
      )
  ) THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc detail record is not found or caller has insufficient access'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    h.id AS hr_emploc_id,
    h.applicant_name,
    h.vcode,
    h.vacancy_id,
    h.vacancy_code_snapshot,
    h.position_id_snapshot,
    h.position AS position_title,
    h.assignment_type::text AS assignment_type,
    h.roving_assignment_id,
    h.covered_stores,
    h.account_id,
    a.account_name,
    a.group_id,
    g.group_name,
    h.store_id,
    h.store_name,
    h.hr_status,
    h.status,
    h.emploc_no,
    h.employee_no,
    h.date_requested,
    h.created_at,
    h.hired_date,
    h.deployed_by_user_id,
    h.hrco_user_id_snapshot,
    h.hrco_name,
    h.employee_lookup_found,
    h.employee_lookup_synced_at,
    h.employee_lookup_remarks,
    h.employee_name_snapshot,
    h.birthdate_snapshot,
    h.civil_status_snapshot,
    h.requirement_overall_status,
    h.ops_remarks,
    h.hr_remarks,
    h.hr_rejection_reason,
    h.hr_reviewed_by,
    h.hr_reviewed_at,

    -- Deficiency Summary
    CASE
      WHEN h.correction_reason IS NULL THEN jsonb_build_object('active_count', 0, 'issues', '[]'::jsonb)
      ELSE jsonb_build_object(
        'active_count', CASE WHEN jsonb_typeof(h.correction_reason) = 'array' THEN jsonb_array_length(h.correction_reason) ELSE 1 END,
        'issues', CASE
          WHEN jsonb_typeof(h.correction_reason) = 'array' THEN (
            SELECT jsonb_agg(
              jsonb_build_object(
                'code', el->>'code',
                'comment', el->>'comment',
                'label', COALESCE((SELECT it.label FROM public.hr_emploc_issue_types it WHERE it.code = el->>'code'), el->>'code')
              )
            )
            FROM jsonb_array_elements(h.correction_reason) el
          )
          ELSE jsonb_build_array(
            jsonb_build_object(
              'code', h.correction_reason->>'type',
              'comment', h.correction_reason->>'comment',
              'label', COALESCE((SELECT it.label FROM public.hr_emploc_issue_types it WHERE it.code = h.correction_reason->>'type'), h.correction_reason->>'type')
            )
          )
        END
      )
    END AS deficiency_summary,

    h.correction_reason,

    -- Correction / Requirement Attachments
    CASE
      WHEN ((h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') AND NOT public.is_super_admin()) OR NOT public.can_view_hr_emploc_docs(h.id) THEN '[]'::jsonb
      ELSE (
        SELECT COALESCE(jsonb_agg(
          jsonb_build_object(
            'id', ca.id,
            'original_filename', ca.original_filename,
            'mime_type', ca.mime_type,
            'size_bytes', ca.size_bytes,
            'stage', ca.stage,
            'uploaded_by', ca.uploaded_by,
            'uploaded_at', ca.uploaded_at,
            'created_at', ca.created_at,
            'storage_path', ca.storage_path,
            'object_path', regexp_replace(ca.storage_path, '^hr-corrections/', ''),
            'can_remove', (
              public.can_upload_hr_emploc_docs(h.id)
              AND (public.is_super_admin() OR ca.uploaded_by = v_profile_id)
            )
          ) ORDER BY ca.uploaded_at DESC
        ), '[]'::jsonb)
        FROM public.hr_emploc_correction_attachments ca
        WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
      )
    END AS correction_attachments,

    -- Deletion Request Overlay Details
    (
      SELECT jsonb_build_object(
        'id', dr.id,
        'status', dr.status,
        'reason', dr.reason,
        'requested_by', dr.requested_by,
        'requested_by_role', dr.requested_by_role,
        'requested_by_user_id', dr.requested_by_user_id,
        'created_at', dr.created_at,
        'deletion_type', dr.deletion_type,
        'original_emploc_id', dr.original_emploc_id,
        'original_hr_status', dr.original_hr_status,
        'reviewed_by', dr.reviewed_by,
        'reviewed_at', dr.reviewed_at,
        'reviewer_remarks', dr.reviewer_remarks,
        'activities', (
          SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
              'id', act.id,
              'activity_type', act.activity_type,
              'performed_by', act.performed_by,
              'performed_by_user_id', act.performed_by_user_id,
              'performed_at', act.performed_at,
              'remarks', act.remarks
            ) ORDER BY act.performed_at DESC
          ), '[]'::jsonb)
          FROM public.hr_emploc_deletion_activities act
          WHERE act.request_id = dr.id
        )
      )
      FROM public.hr_emploc_deletion_requests dr
      WHERE dr.hr_emploc_id = h.id
      ORDER BY dr.created_at DESC
      LIMIT 1
    ) AS deletion_request,

    -- SLA & Aging Computations
    ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))) AS sla_breached,

    CASE
      WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))
        THEN 'breached'
      WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval))
        THEN 'warning'
      ELSE 'normal'
    END AS sla_status,

    (COALESCE(h.date_requested, h.created_at) + INTERVAL '3 days') AS sla_deadline,
    GREATEST(0, (EXTRACT(day FROM (now() - COALESCE(h.date_requested, h.created_at))))::integer) AS aging_days,

    -- Chronological Correction / Action Timeline History
    (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'event_id', t.event_id,
          'event_type', t.event_type,
          'event_label', t.event_label,
          'status_from', t.status_from,
          'status_to', t.status_to,
          'remarks', t.remarks,
          'actor_id', t.actor_id,
          'actor_name', t.actor_name,
          'has_attachment', t.has_attachment,
          'attachment_filename', t.attachment_filename,
          'attachment_size_bytes', t.attachment_size_bytes,
          'created_at', t.created_at
        ) ORDER BY t.created_at ASC
      ), '[]'::jsonb)
      FROM public.get_correction_timeline(h.id) t
    ) AS timeline,

    -- Row action capability presentation UI hints
    jsonb_build_object(
      'can_view_detail', true,
      'hrco_name', COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)),
      'remarks', COALESCE(h.ops_remarks, h.hr_remarks),
      'ops_remarks', h.ops_remarks,
      'hr_remarks', h.hr_remarks,
      'attachment_url', CASE
        WHEN ((h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') AND NOT public.is_super_admin()) OR NOT public.can_view_hr_emploc_docs(h.id) THEN NULL
        ELSE (
          SELECT ca.storage_path
          FROM public.hr_emploc_correction_attachments ca
          WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
          ORDER BY ca.uploaded_at DESC
          LIMIT 1
        )
      END,
      'attachment_file_name', CASE
        WHEN ((h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') AND NOT public.is_super_admin()) OR NOT public.can_view_hr_emploc_docs(h.id) THEN NULL
        ELSE (
          SELECT ca.original_filename
          FROM public.hr_emploc_correction_attachments ca
          WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
          ORDER BY ca.uploaded_at DESC
          LIMIT 1
        )
      END,
      'doc_count', CASE
        WHEN (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') AND NOT public.is_super_admin() THEN 0
        ELSE (
          SELECT count(*)::int
          FROM public.hr_emploc_correction_attachments ca
          WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
        )
      END,
      'attachments', CASE
        WHEN ((h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') AND NOT public.is_super_admin()) OR NOT public.can_view_hr_emploc_docs(h.id) THEN '[]'::jsonb
        ELSE COALESCE((
          SELECT jsonb_agg(
            jsonb_build_object(
              'id', ca.id,
              'original_filename', ca.original_filename,
              'mime_type', ca.mime_type,
              'size_bytes', ca.size_bytes,
              'stage', ca.stage,
              'storage_path', ca.storage_path,
              'object_path', regexp_replace(ca.storage_path, '^hr-corrections/', ''),
              'uploaded_by', ca.uploaded_by,
              'uploaded_at', ca.uploaded_at,
              'created_at', ca.created_at,
              'can_remove', (
                public.can_upload_hr_emploc_docs(h.id)
                AND (public.is_super_admin() OR ca.uploaded_by = v_profile_id)
              )
            ) ORDER BY ca.uploaded_at DESC
          )
          FROM public.hr_emploc_correction_attachments ca
          WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
        ), '[]'::jsonb)
      END,
      'can_request_deletion', (
        h.status <> 'Moved to Plantilla'
        AND h.hr_status <> 'Pending Deletion'
        AND NOT EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
        AND (v_role_level >= 70 OR v_role_name IN ('OM', 'HRCO', 'ATL', 'TL', 'ATL/TL') OR public.i_am_ops() OR public.i_have_full_access())
      ),
      'can_withdraw_deletion_request', (
        EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
        AND (
          public.i_have_full_access()
          OR EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending' AND dr.requested_by_user_id = v_profile_id
          )
        )
      ),
      'can_approve_deletion', (
        (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        AND EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
      ),
      'can_reject_deletion', (
        (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        AND EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
      ),
      'can_edit_emploc', (
        public.can_edit_deployed_hr_emploc()
        AND (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred')
      ),
      'can_revert_to_pending', (
        public.can_edit_deployed_hr_emploc()
        AND (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred')
      ),
      'can_approve_correction', (
        public.can_tag_or_review_hr_emploc()
        AND h.hr_status = 'For Review'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_revert_correction', (
        public.can_tag_or_review_hr_emploc()
        AND h.hr_status = 'For Review'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_review_correction', (
        public.can_tag_or_review_hr_emploc()
        AND h.hr_status = 'For Review'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_upload_docs', public.can_upload_hr_emploc_docs(h.id),
      'can_submit_requirements', (
        public.can_upload_hr_emploc_docs(h.id)
        AND h.hr_status = 'Pending'
      ),
      'can_view_docs', public.can_view_hr_emploc_docs(h.id),
      'can_submit_correction', (
        public.can_upload_hr_emploc_docs(h.id)
        AND h.hr_status = 'For Correction'
      ),
      'can_move_to_plantilla', false,
      'can_tag_deficiency', (
        public.can_tag_or_review_hr_emploc()
        AND h.hr_status = 'For Emploc'
        AND h.status <> 'Moved to Plantilla'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_assign_employee_no', (
        public.can_assign_pending_hr_emploc()
        AND COALESCE(h.employee_no, '') = ''
        AND h.status <> 'Moved to Plantilla'
        AND h.hr_status IN ('Pending', 'For Emploc')
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_review_deletion', (
        (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        AND EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
      )
    ) AS row_capabilities
  FROM public.hr_emploc h
  LEFT JOIN public.accounts a ON a.id = h.account_id
  LEFT JOIN public.groups g ON g.id = a.group_id
  WHERE h.id = p_hr_emploc_id
    AND h.deleted_at IS NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_web_hr_emploc_detail(uuid) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_web_hr_emploc_detail(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
