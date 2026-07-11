-- ohm#f4k2x9m8q — Fix Coverage Hire Pipeline: Missing plantilla_store_links + Contact Propagation
--
-- ADR-001 COMPLIANT: this migration does NOT compute, touch, or reintroduce HC Share.
-- It restores two pipeline data-propagation gaps confirmed by direct code + live schema
-- inspection (staging qqiiznmqxfoamqytjica):
--
-- DEFECT 1 (Coverage-specific): move_to_plantilla()'s CGCODE coverage sub-path
--   (v_emp.coverage_slot_id IS NOT NULL) inserted the plantilla row but never inserted
--   into plantilla_store_links, unlike the sibling Roving branch just above it in the
--   same function. fn_sync_employee_store_allocations derives employee_store_allocations
--   footprints by joining plantilla_store_links on coverage_group_id, so a Coverage hire
--   with zero store-link rows produced zero ESA rows: Stores tab shows "-" for that
--   employee, and any ESA-derived active_store_count/filled_hc read as empty/0.
--
-- DEFECT 2 (pipeline-wide, not Coverage-specific): hr_emploc.contact_number_snapshot and
--   plantilla.contact_no both exist as columns but no INSERT site in the onboarding ->
--   hire pipeline ever populated them. This migration wires the Coverage onboarding path
--   (confirm_coverage_group_onboarding) and all 4 move_to_plantilla branches (pool,
--   roving, CGCODE coverage, pure stationary) to carry contact_number_snapshot through.
--
-- Reference pattern for Patch 1 is the existing Roving branch (same function, a few
-- lines above) and the create_coverage_group live-employee branch in
-- _execute_approved_coverage_request (same file, ~line 624-653), both of which already
-- insert plantilla_store_links + call fn_sync_employee_store_allocations(employee_no).
--
-- No new tables. No schema invention beyond adding data to existing nullable columns.
-- No changes to coverage_group_stores.hc_share or any HC Share computation.

-- ============================================================================
-- PATCH 3: contact_number_snapshot propagation — Coverage onboarding
-- ============================================================================
CREATE OR REPLACE FUNCTION public.confirm_coverage_group_onboarding(p_applicant_id uuid, p_selected_store_ids uuid[], p_hired_by_user_id uuid DEFAULT NULL::uuid, p_hired_date date DEFAULT NULL::date, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role         text    := public.get_my_role();
  v_role_level   int     := COALESCE(public.get_my_role_level(), 0);
  v_profile_id   uuid    := public.get_my_profile_id();
  v_actor_name   text    := public.get_my_full_name();
  v_app          public.applicants%ROWTYPE;
  v_group        public.coverage_groups%ROWTYPE;
  v_hr           public.hr_emploc%ROWTYPE;
  v_hired_by_id  uuid;
  v_store_record record;
  v_covered_json jsonb   := '[]'::jsonb;
  v_store_id     uuid;
BEGIN
  -- 1. RBAC Guard
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Data Team, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- 2. Fetch and lock applicant
  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id FOR UPDATE;
  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant not found or archived' USING ERRCODE = 'P0002';
  END IF;

  IF v_app.coverage_group_id IS NULL OR v_app.coverage_slot_id IS NULL THEN
    RAISE EXCEPTION 'applicant is not assigned to a coverage group slot' USING ERRCODE = '22023';
  END IF;

  IF COALESCE(v_app.status, 'New') IN ('Failed', 'Backout', 'Did Not Report', 'Rejected by Ops') THEN
    RAISE EXCEPTION 'cannot onboard: applicant is in terminal status %', v_app.status USING ERRCODE = '22023';
  END IF;

  -- 3. Fetch and lock coverage group
  SELECT * INTO v_group FROM public.coverage_groups WHERE id = v_app.coverage_group_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage group not found' USING ERRCODE = 'P0002';
  END IF;

  -- 4. Scope Guard
  IF NOT public.i_have_full_access() AND NOT (v_group.account_id = ANY(public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: coverage group is outside caller scope' USING ERRCODE = '42501';
  END IF;

  IF array_length(p_selected_store_ids, 1) IS NULL OR array_length(p_selected_store_ids, 1) < 1 THEN
    RAISE EXCEPTION 'at least one store must be selected' USING ERRCODE = '22023';
  END IF;

  -- 5. Build covered_stores JSONB array and validate footprint
  FOR v_store_id IN SELECT DISTINCT unnest(p_selected_store_ids) LOOP
    SELECT s.store_name, cgs.is_anchor INTO v_store_record
      FROM public.coverage_group_stores cgs
      JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.coverage_group_id = v_group.id
       AND cgs.store_id = v_store_id
       AND cgs.archived_at IS NULL;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'store % is not part of active coverage group footprint', v_store_id USING ERRCODE = '22023';
    END IF;

    v_covered_json := v_covered_json || jsonb_build_object(
      'store_id',   v_store_id,
      'store_name', v_store_record.store_name,
      'is_anchor',  v_store_record.is_anchor
    );
  END LOOP;

  v_hired_by_id := COALESCE(p_hired_by_user_id, v_profile_id);

  -- 6. Update applicant status
  UPDATE public.applicants
     SET status             = 'Confirmed Onboard',
         hired_date         = COALESCE(p_hired_date, hired_date, CURRENT_DATE),
         hired_at           = COALESCE(hired_at, NOW()),
         hired_by           = v_actor_name,
         hired_by_team      = v_role,
         hired_by_user_id   = v_hired_by_id,
         deployed_by_user_id = v_profile_id,
         updated_at         = NOW(),
         updated_by         = v_profile_id
   WHERE id = p_applicant_id;

  -- 7. Insert Coverage HR Emploc.
  --    vcode = NULL            : fk_hr_emploc_vcode skips NULL values.
  --    vacancy_code_snapshot   : CGCODE for display/traceability; no FK.
  --    contact_number_snapshot : ohm#f4k2x9m8q — propagate applicant contact forward
  --                              (was previously dropped at this step).
  INSERT INTO public.hr_emploc (
    applicant_name, applicant_name_snapshot, applicant_id,
    vcode, vacancy_code_snapshot,
    account, account_id, position_id_snapshot, position,
    status, hr_status, hired_date,
    deployed_by_user_id, created_by, updated_by, date_requested,
    assignment_type, coverage_group_id, coverage_slot_id, covered_stores,
    ops_remarks, contact_number_snapshot
  ) VALUES (
    v_app.full_name, v_app.full_name, v_app.id,
    NULL, v_group.coverage_code,
    (SELECT account_name FROM public.accounts WHERE id = v_group.account_id),
    v_group.account_id, v_group.position_id,
    (SELECT position_name FROM public.positions WHERE id = v_group.position_id),
    'Pending Emploc', 'Pending', COALESCE(p_hired_date, CURRENT_DATE),
    v_profile_id, v_profile_id, v_profile_id, NOW(),
    'Coverage'::public.hr_emploc_assignment_type,
    v_group.id, v_app.coverage_slot_id, v_covered_json,
    p_remarks, v_app.contact_number
  )
  RETURNING * INTO v_hr;

  -- 8. Populate hr_emploc_store_links for each selected store.
  --    vcode = NULL            : avoids uq_hr_emploc_store_links_emploc_vcode_active
  --                              collision (all Coverage links share the same CGCODE).
  --                              NULL values are treated as distinct in B-tree indexes.
  --    coverage_slot_id        : full slot traceability per store link.
  FOR v_store_id IN SELECT DISTINCT unnest(p_selected_store_ids) LOOP
    SELECT s.store_name, cgs.is_anchor INTO v_store_record
      FROM public.coverage_group_stores cgs
      JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.coverage_group_id = v_group.id
       AND cgs.store_id = v_store_id
       AND cgs.archived_at IS NULL;

    INSERT INTO public.hr_emploc_store_links (
      hr_emploc_id, coverage_group_id, coverage_slot_id, store_id,
      vcode, store_name, account,
      status, confirmed_at, confirmed_by, created_by, updated_by
    ) VALUES (
      v_hr.id, v_group.id, v_app.coverage_slot_id, v_store_id,
      NULL, v_store_record.store_name, v_hr.account,
      'Confirmed', NOW(), v_profile_id, v_profile_id, v_profile_id
    );
  END LOOP;

  -- 9. Transition slot from pipeline -> hr_processing
  PERFORM public.fn_sync_coverage_slot_to_hr_processing(
    p_coverage_slot_id => v_app.coverage_slot_id,
    p_applicant_id     => v_app.id,
    p_performed_by     => v_profile_id,
    p_source_fn        => 'confirm_coverage_group_onboarding'
  );

  -- 10. Log activity
  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    v_app.full_name,
    v_group.coverage_code,
    'confirmed_onboard',
    'Coverage applicant confirmed onboard to ' || array_to_string(p_selected_store_ids::text[], ', '),
    v_actor_name,
    jsonb_build_object(
      'applicant_id',       v_app.id,
      'hr_emploc_id',       v_hr.id,
      'coverage_group_id',  v_group.id,
      'coverage_slot_id',   v_app.coverage_slot_id,
      'selected_stores',    v_covered_json
    )
  );

  RETURN jsonb_build_object(
    'ok',                true,
    'hr_emploc_id',      v_hr.id,
    'coverage_group_id', v_group.id,
    'coverage_slot_id',  v_app.coverage_slot_id
  );
END;
$function$;

-- ============================================================================
-- PATCH 1 + 2 + 4: move_to_plantilla — store links + ESA sync (CGCODE branch)
--                   + contact_no propagation (all 4 branches)
-- ============================================================================
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
      contact_no,
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

    -- VCODE fallback: close any remaining Open vacancy for this VCODE
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
      contact_no,
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

    -- VCODE fallback: close any remaining Open vacancy for the roving VCODE
    -- (v_emp.vcode is NULL for roving masters — this is a safe no-op)
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
        v_actor, v_actor, v_actor,
        NOW(), NOW()
      )
      RETURNING * INTO v_pl;

      -- ohm#f4k2x9m8q — mirror the Roving branch above: populate
      -- plantilla_store_links from confirmed hr_emploc_store_links so
      -- fn_sync_employee_store_allocations has a footprint to derive ESA
      -- rows from. hr_emploc_store_links.vcode is NULL for Coverage rows
      -- (shared CGCODE collision avoidance — see confirm_coverage_group_
      -- onboarding), so the per-store vcode is resolved from stores.vcode
      -- via store_id, matching the pattern already used in
      -- _execute_approved_coverage_request's create_coverage_group branch.
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

      -- Close carrier CGCODE vacancy via vacancy_id if available (unchanged)
      IF v_emp.vacancy_id IS NOT NULL THEN
        UPDATE vacancies
           SET status     = 'Filled',
               updated_at = NOW(),
               updated_by = v_actor
         WHERE id = v_emp.vacancy_id;
      END IF;

      -- VCODE fallback: close any remaining Open carrier vacancy (unchanged)
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
      -- OHM2026_0081: fn_sync_slot_to_occupied is called HERE (before the
      -- vacancy update) so the slot is 'occupied' when the NOT EXISTS guard
      -- evaluates. This prevents premature 'Filled' + archival on the first
      -- hire of a multi-slot (HC>1) vacancy.

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
        v_actor, v_actor, v_actor, NOW(), NOW()
      )
      RETURNING * INTO v_pl;

      -- OHM2026_0081 §1a: sync slot to occupied BEFORE the vacancy status
      -- update. After this call the current slot's slot_status = 'occupied',
      -- so the NOT EXISTS guard below correctly sees only the remaining
      -- unfilled slots when deciding whether to close the vacancy.
      PERFORM public.fn_sync_slot_to_occupied(
        p_vcode        => v_emp.vcode,
        p_hr_emploc_id => p_id,
        p_plantilla_id => v_pl.id,
        p_performed_by => v_actor,
        p_source_fn    => 'move_to_plantilla'
      );

      -- OHM2026_0081 §1b: close via vacancy_id only when all slots occupied.
      -- For HC=1 vacancies the NOT EXISTS is satisfied immediately (the just-
      -- synced slot is the only one). For HC=N, it fires only on the N-th hire.
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

      -- OHM2026_0081 §1b: VCODE fallback — same NOT EXISTS guard.
      -- Only marks Filled (and triggers on_vacancy_filled_archive -> is_archived)
      -- when truly every slot is occupied.
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

    END IF; -- end coverage/pure-stationary split

  END IF; -- end pool/roving/stationary split

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

  -- OHM2026_0081 §1c: fn_sync_slot_to_occupied is now called inside the pure-
  -- stationary sub-path (before the vacancy update). Only fn_sync_coverage_slot_
  -- to_active remains here for the CGCODE coverage path.
  -- Pool path and roving path never called fn_sync_slot_to_occupied (unchanged).
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
