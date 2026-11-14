-- ============================================================================
-- Migration: 20262606000019_slot_authority_lockdown.sql
-- Prompt ID: ohm#7k2d9f4a
-- Date:      2026-08-03
-- Purpose:   ADR-001 database-level enforcement (D1) - make fn_set_slot_status
--            the single authority for plantilla_slots.slot_status transitions.
--
-- Scope of this migration:
--   1. fn_set_slot_status - transition-matrix extensions (see below).
--   2. move_to_plantilla - slot reserve (open->hr_processing) and finalize
--      (hr_processing->filled) rewired through fn_set_slot_status.
--   3. _execute_approved_coverage_request - all 5 slot_status write sites
--      rewired through fn_set_slot_status; structural (non-status) column
--      writes remain direct.
--   4. tag_backout - ADR-001 audit CASE 1 fix: a backout now releases the
--      linked plantilla slot (-> 'open') in the same transaction, via
--      fn_set_slot_status. Blocked transition = FATAL (raises).
--   5. Grant lockdown: UPDATE on public.plantilla_slots revoked from anon and
--      authenticated (table-level and column-level), idempotent/guarded.
--
-- Transition-matrix extensions in fn_set_slot_status:
--   a. closed/hc_reduced -> open now ALLOWED, but only with reason_code IN
--      ('HC_READD','COVERAGE_STORE_REMOVED','COVERAGE_GROUP_DISSOLVED')
--      (explicit re-add / coverage-conversion workflows). All other writes
--      out of terminal states remain blocked.
--   b. occupied/filled -> open action_type mapping extended:
--      'BACKOUT' -> 'backout_released', 'COVERAGE_GROUP_CREATED' ->
--      'employee_separated', 'COVERAGE_STORE_REMOVED' ->
--      'coverage_store_removed' (previously everything not TRANSFER_OUT was
--      logged as 'resigned').
--
-- BEFORE-state notes (live staging bodies snapshotted via pg_get_functiondef
-- on 2026-08-03; snapshots kept in session scratchpad sa1_before_*.sql):
--   - move_to_plantilla: 3 direct UPDATE public.plantilla_slots sites
--     (reserve, finalize, exception-handler revert). The exception-handler
--     revert is intentionally KEPT as a direct write: it is a compensation
--     path inside an aborting transaction; routing it through the authority
--     could mask the original error and its slot_history row would be rolled
--     back with the transaction anyway.
--   - _execute_approved_coverage_request: 5 direct slot_status write sites
--     (create_coverage_group vacate; remove_store/convert reopen x2;
--     dissolve_coverage_group reopen x2). Bespoke slot_history inserts are
--     KEPT unchanged for report compatibility; fn_set_slot_status adds its
--     own audit row (additive).
--   - tag_backout: previously reset only the COVERAGE slot and never released
--     the plantilla slot (audit CASE 1).
--   - Direct writers intentionally NOT rewired (bulk archival is not a
--     lifecycle transition; all are SECURITY DEFINER + is_super_admin()
--     gated + search_path pinned, verified live 2026-08-03):
--     fn_archive_all_operational_data, fn_archive_plantilla_data,
--     fn_qa_archive_operational_data_reset,
--     fn_qa_rollback_operational_data_reset, fn_rollback_archive_batch.
--   - create_plantilla_slot_from_request: its only plantilla_slots UPDATE
--     writes source_hc_request_id metadata (never slot_status) - no change.
--   - Grants BEFORE: anon/authenticated had NO UPDATE/INSERT grant on
--     plantilla_slots (only SELECT for authenticated plus REFERENCES/TRIGGER
--     oddities); the revoke below is an idempotent assertion.
-- ============================================================================

-- --------------------------------------------------------------------------
-- 1. fn_set_slot_status - slot authority (matrix extensions)
-- --------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_set_slot_status(p_slot_id uuid, p_new_status text, p_reason_code text DEFAULT NULL::text, p_performed_by uuid DEFAULT NULL::uuid, p_remarks text DEFAULT NULL::text, p_occupant_plantilla_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_slot           record;
  v_from_status    text;
  v_action_type    text;
  v_history_id     uuid;
  v_transition_ok  boolean := false;
  v_blocked_reason text;
BEGIN
  IF p_slot_id IS NULL THEN
    RAISE EXCEPTION 'fn_set_slot_status: p_slot_id is required';
  END IF;

  IF p_new_status NOT IN (
    'open', 'pipeline', 'hr_processing', 'occupied', 'filled', 'closed', 'hc_reduced'
  ) THEN
    RAISE EXCEPTION 'fn_set_slot_status: unknown status value ''%''', p_new_status;
  END IF;

  SELECT * INTO v_slot
  FROM public.plantilla_slots
  WHERE id = p_slot_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_set_slot_status: slot % not found', p_slot_id;
  END IF;

  v_from_status := v_slot.slot_status;

  IF v_from_status = p_new_status THEN
    RETURN jsonb_build_object(
      'status',      'no_op',
      'slot_id',     p_slot_id,
      'from_status', v_from_status,
      'to_status',   p_new_status
    );
  END IF;

  -- Transition matrix
  -- ohm#7k2d9f4a: terminal states may be re-opened ONLY through an explicit,
  -- named re-add / coverage-conversion workflow (reason-code gated).
  IF v_from_status IN ('closed', 'hc_reduced') AND p_new_status = 'open'
     AND p_reason_code IN ('HC_READD', 'COVERAGE_STORE_REMOVED', 'COVERAGE_GROUP_DISSOLVED') THEN
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status IN ('closed', 'hc_reduced') THEN
    v_transition_ok  := false;
    v_blocked_reason := format(
      '%s is terminal under automation; re-opening a slot requires an HC re-add workflow',
      v_from_status
    );

  ELSIF v_from_status = 'open' AND p_new_status = 'pipeline' THEN
    v_transition_ok := true;
    v_action_type   := 'pipeline';

  ELSIF v_from_status = 'open' AND p_new_status IN ('occupied', 'filled') THEN
    IF p_occupant_plantilla_id IS NULL THEN
      v_transition_ok  := false;
      v_blocked_reason := format('%s→%s (transfer-in) requires p_occupant_plantilla_id', v_from_status, p_new_status);
    ELSE
      v_transition_ok := true;
      v_action_type   := 'transfer_in';
    END IF;

  ELSIF v_from_status = 'open' AND p_new_status = 'closed' THEN
    v_transition_ok := true;
    v_action_type   := 'closed';

  ELSIF v_from_status = 'open' AND p_new_status = 'hc_reduced' THEN
    v_transition_ok := true;
    v_action_type   := 'hc_reduced';

  ELSIF v_from_status = 'open' AND p_new_status = 'hr_processing' THEN
    v_transition_ok := true;
    v_action_type   := 'import_reserved';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'hr_processing' THEN
    v_transition_ok := true;
    v_action_type   := 'hr_processing';

  ELSIF v_from_status = 'pipeline' AND p_new_status IN ('occupied', 'filled') THEN
    v_transition_ok  := false;
    v_blocked_reason := 'pipeline→occupied is blocked: slot must pass through hr_processing first';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'closed' THEN
    v_transition_ok := true;
    v_action_type   := 'closed';

  ELSIF v_from_status = 'hr_processing' AND p_new_status IN ('occupied', 'filled') THEN
    IF p_occupant_plantilla_id IS NULL THEN
      v_transition_ok  := false;
      v_blocked_reason := format('%s→%s requires p_occupant_plantilla_id', v_from_status, p_new_status);
    ELSE
      v_transition_ok := true;
      v_action_type   := 'occupied';
    END IF;

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'pipeline' THEN
    v_transition_ok := true;
    v_action_type   := 'import_rejected';

  ELSIF v_from_status IN ('occupied', 'filled') AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := CASE p_reason_code
                          WHEN 'TRANSFER_OUT' THEN 'transfer_out'
                          WHEN 'BACKOUT' THEN 'backout_released'
                          WHEN 'COVERAGE_GROUP_CREATED' THEN 'employee_separated'
                          WHEN 'COVERAGE_STORE_REMOVED' THEN 'coverage_store_removed'
                          ELSE 'resigned'
                        END;

  ELSIF v_from_status IN ('occupied', 'filled') AND p_new_status IN ('pipeline', 'hr_processing') THEN
    v_transition_ok  := false;
    v_blocked_reason := format(
      '%s→%s is blocked: occupant must separate first (%s→open), '
      'then the slot re-enters recruitment', v_from_status, p_new_status, v_from_status
    );

  ELSE
    v_transition_ok  := false;
    v_blocked_reason := format('%s→%s is not a supported transition', v_from_status, p_new_status);
  END IF;

  IF NOT v_transition_ok THEN
    RETURN jsonb_build_object(
      'status',         'blocked',
      'slot_id',        p_slot_id,
      'from_status',    v_from_status,
      'to_status',      p_new_status,
      'blocked_reason', v_blocked_reason
    );
  END IF;

  -- Apply transition
  UPDATE public.plantilla_slots
  SET
    slot_status                   = p_new_status,
    current_occupant_plantilla_id = CASE
      WHEN p_new_status IN ('occupied', 'filled') THEN p_occupant_plantilla_id
      WHEN p_new_status IN ('open', 'closed', 'hc_reduced') THEN NULL
      ELSE current_occupant_plantilla_id
    END,
    closed_at                     = CASE
      WHEN p_new_status IN ('closed', 'hc_reduced') THEN now()
      ELSE closed_at
    END,
    closed_by                     = CASE
      WHEN p_new_status IN ('closed', 'hc_reduced') THEN p_performed_by
      ELSE closed_by
    END,
    closure_reason_code           = CASE
      WHEN p_new_status IN ('closed', 'hc_reduced') THEN p_reason_code
      ELSE closure_reason_code
    END,
    updated_at                    = now(),
    updated_by                    = p_performed_by
  WHERE id = p_slot_id;

  INSERT INTO public.slot_history (
    slot_id,
    account_id,
    action_type,
    old_value,
    new_value,
    reason_code,
    performed_by,
    remarks
  ) VALUES (
    p_slot_id,
    v_slot.account_id,
    v_action_type,
    v_from_status,
    p_new_status,
    p_reason_code,
    p_performed_by,
    p_remarks
  )
  RETURNING id INTO v_history_id;

  RETURN jsonb_build_object(
    'status',      'ok',
    'slot_id',     p_slot_id,
    'from_status', v_from_status,
    'to_status',   p_new_status,
    'action_type', v_action_type,
    'reason_code', p_reason_code,
    'history_id',  v_history_id
  );
END;
$function$;

-- --------------------------------------------------------------------------
-- 2. move_to_plantilla - rewired through slot authority
-- --------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.move_to_plantilla(p_id uuid)
 RETURNS plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_emp             public.hr_emploc;
  v_pl              public.plantilla;
  v_actor           uuid := get_my_profile_id();
  v_is_pool         boolean := false;
  v_pool_type_id    uuid;
  v_home_account_id uuid;
  v_home_acct       public.accounts;
  v_slot_id         uuid := NULL;
  v_slot_auth       jsonb;
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

  -- ── 1. ATOMIC SLOT SELECTION & RESERVATION (Stationary non-pool non-roving path) ──
  IF NOT v_is_pool AND COALESCE(v_emp.assignment_type, 'Stationary') <> 'Roving' AND v_emp.coverage_slot_id IS NULL THEN
    -- Atomic slot selection using FOR UPDATE SKIP LOCKED
    SELECT id INTO v_slot_id
    FROM public.plantilla_slots
    WHERE legacy_vcode = v_emp.vcode
      AND slot_status = 'open'
    ORDER BY created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    -- 2. HANDLE NO AVAILABLE SLOT
    IF v_slot_id IS NULL THEN
      -- Fallback: check if hr_emploc already holds a reserved slot in open/hr_processing state
      IF v_emp.slot_id IS NOT NULL THEN
        SELECT id INTO v_slot_id
        FROM public.plantilla_slots
        WHERE id = v_emp.slot_id
          AND slot_status IN ('open', 'hr_processing')
        FOR UPDATE SKIP LOCKED;
      END IF;

      IF v_slot_id IS NULL THEN
        RAISE EXCEPTION 'No available headcount for this VCode.' USING ERRCODE = '22023';
      END IF;
    END IF;

    -- 3. TRANSITION SLOT STATE (RESERVE FIRST)
    -- ohm#7k2d9f4a: routed through fn_set_slot_status (slot authority)
    v_slot_auth := public.fn_set_slot_status(
      p_slot_id      => v_slot_id,
      p_new_status   => 'hr_processing',
      p_reason_code  => NULL,
      p_performed_by => v_actor,
      p_remarks      => 'move_to_plantilla: slot reserved for hr_emploc ' || p_id::text
    );
    IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
      RAISE EXCEPTION 'move_to_plantilla: slot % reservation blocked: %',
        v_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- ── 4. INSERT INTO PLANTILLA ───────────────────────────────────────────────

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

    -- VCODE fallback: close any remaining Open vacancy for the roving VCODE
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
      -- ── CGCODE COVERAGE SUB-PATH ───────────────────────────────────────────
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

      -- VCODE fallback: close any remaining Open carrier vacancy
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

    END IF; -- end coverage/pure-stationary split

  END IF; -- end pool/roving/stationary split

  -- ── 5. FINALIZE SLOT (Mark slot filled & link occupant) ───────────────────
  IF v_slot_id IS NOT NULL THEN
    -- ohm#7k2d9f4a: routed through fn_set_slot_status (slot authority)
    v_slot_auth := public.fn_set_slot_status(
      p_slot_id               => v_slot_id,
      p_new_status            => 'filled',
      p_reason_code           => NULL,
      p_performed_by          => v_actor,
      p_remarks               => 'move_to_plantilla: slot filled by plantilla ' || v_pl.id::text,
      p_occupant_plantilla_id => v_pl.id
    );
    IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
      RAISE EXCEPTION 'move_to_plantilla: slot % finalization blocked: %',
        v_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- ── Vacancy Closure for Pure Stationary Path ─────────────────────────────
  IF NOT v_is_pool AND COALESCE(v_emp.assignment_type, 'Stationary') <> 'Roving' AND v_emp.coverage_slot_id IS NULL THEN
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

  IF v_emp.coverage_slot_id IS NOT NULL THEN
    PERFORM public.fn_sync_coverage_slot_to_active(
      p_coverage_slot_id => v_emp.coverage_slot_id,
      p_plantilla_id     => v_pl.id,
      p_performed_by     => v_actor,
      p_source_fn        => 'move_to_plantilla'
    );
  END IF;

  RETURN v_pl;

-- ── 6. FAILURE SAFETY (Rollback Revert) ──────────────────────────────────────
EXCEPTION WHEN OTHERS THEN
  IF v_slot_id IS NOT NULL THEN
    UPDATE public.plantilla_slots
    SET slot_status = 'open',
        updated_at = NOW()
    WHERE id = v_slot_id;
  END IF;
  RAISE;
END
$function$;

-- --------------------------------------------------------------------------
-- 3. _execute_approved_coverage_request - rewired through slot authority
-- --------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._execute_approved_coverage_request(p_request coverage_requests, p_actor_id uuid, p_actor_name text, p_actor_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  -- ── iteration / loop cursors
  v_store_id               uuid;
  v_pl                     record;

  -- ── remove_store semantics (corrected per ohm#25f6a6ra)
  v_removed_store_ids      uuid[];
  v_remaining_store_ids    uuid[];
  v_remaining_count        integer;

  -- ── add_store
  v_store_ids              uuid[];
  v_replacement_store_ids  uuid[];

  v_below_minimum_action   text;

  -- ── reporting
  v_existing_cg_code       text;
  v_anchor_removed         boolean := false;
  v_stores_added           integer := 0;
  v_stores_removed         integer := 0;
  v_group_archived         boolean := false;
  v_notes                  text[]  := ARRAY[]::text[];

  -- ── stationary-conversion helpers
  v_remaining_store_id     uuid;
  v_remaining_store_name   text;
  v_remaining_store_vcode  text;

  -- ── imported-employee helpers
  v_active_allocs          integer;

  -- ── vacancy / slot reopening helpers
  v_existing_slot_id       uuid;
  v_new_slot_id            uuid;
  v_rows_updated           integer;
  v_slot_auth              jsonb;
  v_store_account_id       uuid;
  v_store_group_id         uuid;
  v_store_vcode            text;
  v_store_name_local       text;
  v_store_account_name     text;
  v_store_position         text;
  v_store_employment_type  text;
  v_store_position_id      uuid;
  v_store_province_id      uuid;   -- always NULL; stores has no province_id
  v_store_area             text;
  v_store_chain_id         uuid;

  -- ── Bug 1 fix: pre-resolved group_id fallback from CG account
  v_cg_account_group_id    uuid;

  -- ── Bug 2 fix: pre-resolved position from coverage_groups → positions
  v_cg_position_name       text;
  v_cg_position_id         uuid;

  -- ── GAP-02 dissolve variables
  v_employee_home_stores   jsonb;
  v_retained_store_ids     uuid[];
  v_dissolved_store_ids    uuid[];
  v_employees_converted    integer := 0;
  v_vacancies_reopened     integer := 0;

  -- ── create_coverage_group variables
  v_new_cg_id              uuid;
  v_cg_code                text;
  v_store_count            integer;
  v_slot_ordinal           integer := 0;
  v_slot_id                uuid;
  v_anchor_store_name      text;
  v_anchor_store_vcode     text;
  v_old_slot_id            uuid;
  v_old_vcode              text;

  -- ── ohm#4h8w1qz6: anchor position inheritance
  v_anchor_store_id        uuid;
  v_resolved_position_id   uuid;

  -- ── ohm#8a4f71d2 merge_coverage_groups variables
  v_surviving_cg_id        uuid;
  v_merged_cg_id           uuid;
  v_surviving_cg_code      text;
  v_merged_cg_code         text;
  v_stores_transferred     integer := 0;
  v_employees_transferred  integer := 0;
BEGIN

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── create_coverage_group ───────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  IF p_request.request_type = 'create_coverage_group'::public.request_type THEN
    v_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);
    v_store_count := COALESCE(array_length(v_store_ids, 1), 0);

    IF v_store_count < 2 THEN
      RAISE EXCEPTION 'Coverage Group must have at least 2 member stores.' USING ERRCODE = '23514';
    END IF;

    v_new_cg_id := gen_random_uuid();
    v_cg_code := public.fn_generate_cgcode_for_account(p_request.account_id);

    -- ── ohm#4h8w1qz6 Fix 2 (corrected 20260706000013): resolve position_id from
    -- anchor store BEFORE insert. plantilla_slots has NO position_id column — only
    -- text `position`. Prefer the anchor's active plantilla occupant's
    -- plantilla.position_id; fall back to matching plantilla_slots.position
    -- (text) against positions.position_name for an open slot. NULL if neither.
    v_anchor_store_id := (p_request.payload ->> 'anchor_store_id')::uuid;

    SELECT pl2.position_id INTO v_resolved_position_id
    FROM public.plantilla pl2
    WHERE pl2.store_id = v_anchor_store_id
      AND pl2.account_id = p_request.account_id
      AND pl2.status = 'Active'
      AND COALESCE(pl2.is_deleted, false) = false
      AND COALESCE(pl2.is_archived, false) = false
      AND pl2.position_id IS NOT NULL
    ORDER BY pl2.updated_at DESC
    LIMIT 1;

    IF v_resolved_position_id IS NULL THEN
      SELECT pos.id INTO v_resolved_position_id
      FROM public.plantilla_slots ps
      JOIN public.positions pos ON pos.position_name = ps.position
      WHERE ps.store_id = v_anchor_store_id
        AND ps.account_id = p_request.account_id
        AND ps.slot_status = 'open'
      ORDER BY ps.created_at DESC
      LIMIT 1;
    END IF;

    -- STEP 1: Create coverage group structure
    INSERT INTO public.coverage_groups (
      id, coverage_code, account_id, position_id,
      employment_type, required_headcount, status,
      area_name, created_by, created_at
    ) VALUES (
      v_new_cg_id, v_cg_code, p_request.account_id, v_resolved_position_id,
      p_request.employment_type, v_store_count, 'open',
      p_request.payload ->> 'area_name', p_actor_id, now()
    );

    SELECT store_name, vcode INTO v_anchor_store_name, v_anchor_store_vcode
    FROM public.stores
    WHERE id = (p_request.payload ->> 'anchor_store_id')::uuid;

    -- STEP 2: Create coverage group member edges
    FOREACH v_store_id IN ARRAY v_store_ids LOOP
      INSERT INTO public.coverage_group_stores (
        coverage_group_id, store_id, is_anchor, added_by
      ) VALUES (
        v_new_cg_id, v_store_id, (v_store_id = (p_request.payload ->> 'anchor_store_id')::uuid), p_actor_id
      );
    END LOOP;

    -- STEP 3 & 4: Evaluate member stores and assign active employees
    v_slot_ordinal := 0;
    FOR v_pl IN (
      SELECT pl.*, a.group_id
      FROM public.plantilla pl
      JOIN public.accounts a ON a.id = pl.account_id
      WHERE pl.store_id = ANY(v_store_ids)
        AND pl.account_id = p_request.account_id
        AND (p_request.position_id IS NULL OR pl.position_id = p_request.position_id)
        AND pl.status = 'Active'
        AND COALESCE(pl.is_deleted, false) = false
        AND COALESCE(pl.is_archived, false) = false
    ) LOOP
      v_slot_id := gen_random_uuid();
      v_slot_ordinal := v_slot_ordinal + 1;

      -- Create active coverage slot row
      INSERT INTO public.coverage_slots (
        id, coverage_group_id, slot_ordinal, slot_status, current_occupant_plantilla_id, created_at, updated_at
      ) VALUES (
        v_slot_id, v_new_cg_id, v_slot_ordinal, 'active', v_pl.id, now(), now()
      );

      -- Update employee plantilla row to roving
      UPDATE public.plantilla
      SET deployment_type = 'Roving',
          coverage_group_id = v_new_cg_id,
          coverage_slot_id = v_slot_id,
          store_id = (p_request.payload ->> 'anchor_store_id')::uuid,
          store_name = v_anchor_store_name,
          vcode = NULL
      WHERE id = v_pl.id;

      -- Vacate/open old stationary slot in plantilla_slots
      SELECT id, legacy_vcode INTO v_old_slot_id, v_old_vcode
      FROM public.plantilla_slots
      WHERE current_occupant_plantilla_id = v_pl.id
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_old_slot_id IS NOT NULL THEN
        -- ohm#7k2d9f4a: routed through fn_set_slot_status (slot authority)
        v_slot_auth := public.fn_set_slot_status(
          p_slot_id      => v_old_slot_id,
          p_new_status   => 'open',
          p_reason_code  => 'COVERAGE_GROUP_CREATED',
          p_performed_by => p_actor_id,
          p_remarks      => 'Employee converted to roving coverage in group ' || v_cg_code || '.'
        );
        IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
          RAISE EXCEPTION 'coverage request: slot % release blocked: %',
            v_old_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
            USING ERRCODE = '22023';
        END IF;

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type,
          old_value, new_value, reason_code,
          performed_by, remarks, created_at
        ) VALUES (
          v_old_slot_id, v_pl.account_id, 'employee_separated',
          'occupied', 'open', 'COVERAGE_GROUP_CREATED',
          p_actor_id, 'Employee converted to roving coverage in group ' || v_cg_code || '.', now()
        );
      END IF;

      -- Reconcile assignments/allocations
      IF v_pl.source_employee_import_batch_id IS NOT NULL
         OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        -- Deactivate old allocations
        UPDATE public.employee_store_allocations
        SET is_active = false,
            effective_end = CURRENT_DATE
        WHERE plantilla_id = v_pl.id AND is_active = true;

        -- Insert new allocations for all group stores
        FOREACH v_store_id IN ARRAY v_store_ids LOOP
          SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
          FROM public.stores WHERE id = v_store_id;

          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          ) VALUES (
            v_pl.id, v_pl.employee_no, v_new_cg_id,
            v_store_id, v_store_vcode, v_store_name_local,
            v_pl.account_id, v_pl.group_id,
            round(1.0 / v_store_count, 4), v_store_count,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, p_actor_id
          );
        END LOOP;
      ELSE
        -- Live employee: deactivate old store links
        UPDATE public.plantilla_store_links
        SET status = 'Resigned',
            deleted_at = now(),
            unlinked_at = now(),
            unlinked_by = p_actor_id
        WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;

        -- Insert new store links for all group stores
        FOREACH v_store_id IN ARRAY v_store_ids LOOP
          SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
          FROM public.stores WHERE id = v_store_id;

          INSERT INTO public.plantilla_store_links (
            plantilla_id,
            coverage_group_id,
            vcode,
            store_name,
            account,
            status,
            linked_at,
            linked_by,
            created_by,
            updated_by
          ) VALUES (
            v_pl.id,
            v_new_cg_id,
            v_store_vcode,
            v_store_name_local,
            (SELECT account_name FROM public.accounts WHERE id = v_pl.account_id),
            'Active',
            now(),
            p_actor_id,
            p_actor_id,
            p_actor_id
          );
        END LOOP;

        PERFORM public.fn_sync_employee_store_allocations(v_pl.employee_no);
      END IF;

      v_employees_converted := v_employees_converted + 1;
      v_notes := v_notes || ARRAY[
        'employee:' || COALESCE(v_pl.employee_name, v_pl.employee_no, v_pl.id::text)
        || '|assigned_to_coverage_group:' || v_cg_code
      ];
    END LOOP;

    -- ── ohm#4h8w1qz6 Fix 1: exactly 1 open coverage_slots row for pure-structure
    IF v_employees_converted = 0 THEN
      INSERT INTO public.coverage_slots (
        coverage_group_id, slot_ordinal, slot_status, current_occupant_plantilla_id, created_at, updated_at
      ) VALUES (
        v_new_cg_id, 1, 'open', NULL, now(), now()
      );
    END IF;

    -- Link request target_coverage_group_id to the new group
    UPDATE public.coverage_requests
    SET target_coverage_group_id = v_new_cg_id
    WHERE id = p_request.id;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 'create_coverage_group',
      'coverage_group_id',            v_new_cg_id,
      'coverage_code',                v_cg_code,
      'stores_added',                 v_store_count,
      'employees_converted',          v_employees_converted,
      'notes',                        to_jsonb(v_notes)
    );

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── add_store ───────────────────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'add_store'::public.request_type THEN
    v_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);

    FOREACH v_store_id IN ARRAY v_store_ids LOOP
      SELECT cg.coverage_code INTO v_existing_cg_code
      FROM public.coverage_group_stores cgs
      JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
      WHERE cgs.store_id = v_store_id
        AND cgs.archived_at IS NULL
        AND cg.archived_at IS NULL
        AND cg.id <> p_request.target_coverage_group_id
      LIMIT 1;

      IF v_existing_cg_code IS NOT NULL THEN
        RAISE EXCEPTION
          'store % is already active in coverage group %; remove it first',
          v_store_id, v_existing_cg_code
          USING ERRCODE = '23514';
      END IF;

      IF EXISTS (
        SELECT 1 FROM public.coverage_group_stores
        WHERE coverage_group_id = p_request.target_coverage_group_id
          AND store_id = v_store_id
          AND archived_at IS NULL
      ) THEN
        RAISE EXCEPTION
          'store % is already an active member of this coverage group',
          v_store_id
          USING ERRCODE = '23514';
      END IF;

      INSERT INTO public.coverage_group_stores (
        coverage_group_id, store_id, is_anchor, added_by
      ) VALUES (
        p_request.target_coverage_group_id, v_store_id, false, p_actor_id
      );
      v_stores_added := v_stores_added + 1;

      FOR v_pl IN (
        SELECT pl.*, a.group_id
        FROM public.plantilla pl
        JOIN public.accounts a ON a.id = pl.account_id
        WHERE pl.coverage_group_id = p_request.target_coverage_group_id
          AND pl.status = 'Active'
          AND pl.is_deleted = false
          AND pl.is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          IF NOT EXISTS (
            SELECT 1 FROM public.employee_store_allocations
            WHERE plantilla_id = v_pl.id AND store_id = v_store_id AND is_active = true
          ) THEN
            SELECT store_name, vcode
            INTO v_remaining_store_name, v_remaining_store_vcode
            FROM public.stores WHERE id = v_store_id;

            INSERT INTO public.employee_store_allocations (
              plantilla_id, employee_no, roving_group_id,
              store_id, vcode, store_name,
              account_id, group_id,
              filled_hc, active_store_count,
              effective_start, is_active,
              source_import_batch_id, created_by
            ) VALUES (
              v_pl.id, v_pl.employee_no, p_request.target_coverage_group_id,
              v_store_id, v_remaining_store_vcode, v_remaining_store_name,
              v_pl.account_id, v_pl.group_id,
              1, 1,
              CURRENT_DATE, true,
              v_pl.source_baseline_import_batch_id, p_actor_id
            );
          END IF;
        END IF;
      END LOOP;
    END LOOP;

    FOR v_pl IN (
      SELECT * FROM public.plantilla
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND status = 'Active'
        AND is_deleted = false
        AND is_archived = false
    ) LOOP
      IF v_pl.source_employee_import_batch_id IS NOT NULL
        OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        SELECT COUNT(*) INTO v_active_allocs
        FROM public.employee_store_allocations
        WHERE plantilla_id = v_pl.id AND is_active = true;

        IF v_active_allocs > 0 THEN
          UPDATE public.employee_store_allocations
          SET active_store_count = v_active_allocs,
              filled_hc = round(1.0 / v_active_allocs, 4)
          WHERE plantilla_id = v_pl.id AND is_active = true;
        END IF;
      END IF;
    END LOOP;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 'add_store',
      'stores_added',                 v_stores_added,
      'stores_removed',               0,
      'group_archived',               false,
      'below_minimum_action_applied', null,
      'notes',                        to_jsonb(v_notes)
    );


  -- ════════════════════════════════════════════════════════════════════════════
  -- ── remove_store / convert_roving_to_stationary ─────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'remove_store'::public.request_type
     OR p_request.request_type = 'convert_roving_to_stationary'::public.request_type
  THEN

    -- Pre-resolve group_id from coverage group's account
    SELECT a.group_id
    INTO v_cg_account_group_id
    FROM public.coverage_groups cg
    JOIN public.accounts a ON a.id = cg.account_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- Pre-resolve position from coverage_groups → positions
    SELECT pos.position_name, cg.position_id
    INTO v_cg_position_name, v_cg_position_id
    FROM public.coverage_groups cg
    LEFT JOIN public.positions pos ON pos.id = cg.position_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- Resolve which stores are being REMOVED
    IF p_request.request_type = 'convert_roving_to_stationary'::public.request_type THEN
      v_remaining_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);
      SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_removed_store_ids
      FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND archived_at IS NULL
        AND NOT (store_id = ANY (v_remaining_store_ids));
      v_remaining_count := COALESCE(array_length(v_remaining_store_ids, 1), 0);
      v_below_minimum_action := 'convert_remaining_to_standalone';
    ELSE
      v_removed_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);

      IF EXISTS (
        SELECT 1 FROM unnest(v_removed_store_ids) AS rid
        WHERE NOT EXISTS (
          SELECT 1 FROM public.coverage_group_stores
          WHERE coverage_group_id = p_request.target_coverage_group_id
            AND store_id = rid
            AND archived_at IS NULL
        )
      ) THEN
        RAISE EXCEPTION
          'remove_store: one or more store_ids are not active members of this coverage group'
          USING ERRCODE = '23514';
      END IF;

      SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_remaining_store_ids
      FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND archived_at IS NULL
        AND NOT (store_id = ANY (v_removed_store_ids));

      v_remaining_count := COALESCE(array_length(v_remaining_store_ids, 1), 0);

      IF v_remaining_count = 0 THEN
        RAISE EXCEPTION
          'remove_store would leave 0 active stores; use dissolve_coverage_group instead'
          USING ERRCODE = '23514';
      ELSIF v_remaining_count = 1 THEN
        v_below_minimum_action := 'convert_remaining_to_standalone';
      ELSE
        v_below_minimum_action := NULL;
      END IF;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = ANY (v_removed_store_ids)
        AND is_anchor = true
        AND archived_at IS NULL
    ) THEN
      v_anchor_removed := true;
      v_notes := v_notes || ARRAY['anchor store removed; group has no active anchor'];
    END IF;

    -- Employee Integrity Lock
    IF v_remaining_count >= 2 THEN
      FOR v_pl IN (
        SELECT pl.*, a.group_id
        FROM public.plantilla pl
        JOIN public.accounts a ON a.id = pl.account_id
        WHERE pl.coverage_group_id = p_request.target_coverage_group_id
          AND pl.status = 'Active'
          AND pl.is_deleted = false
          AND pl.is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          -- Imported employee: count ESA rows that survive after removal
          SELECT COUNT(*) INTO v_active_allocs
          FROM public.employee_store_allocations
          WHERE plantilla_id = v_pl.id
            AND is_active = true
            AND NOT (store_id = ANY(v_removed_store_ids));

          IF v_active_allocs = 0 THEN
            RAISE EXCEPTION
              'Employee integrity lock: removing these stores would leave employee % (%) with 0 active store assignments. '
              'Retain at least one store for this employee, or use Dissolve Coverage Group.',
              COALESCE(v_pl.employee_name, ''), COALESCE(v_pl.employee_no, '')
              USING ERRCODE = '23514';
          END IF;
        ELSE
          -- Non-imported employee: count active store links surviving after removal
          SELECT COUNT(*) INTO v_active_allocs
          FROM public.plantilla_store_links psl
          JOIN public.stores s ON psl.vcode = s.vcode
          WHERE psl.plantilla_id = v_pl.id
            AND psl.deleted_at IS NULL
            AND NOT (s.id = ANY(v_removed_store_ids));

          IF v_active_allocs = 0 THEN
            RAISE EXCEPTION
              'Employee integrity lock: removing these stores would leave employee % (%) with 0 active store assignments. '
              'Retain at least one store for this employee, or use Dissolve Coverage Group.',
              COALESCE(v_pl.employee_name, ''), COALESCE(v_pl.employee_no, '')
              USING ERRCODE = '23514';
          END IF;
        END IF;
      END LOOP;
    END IF;

    -- Branch A: convert_remaining_to_standalone (remaining_count = 1)
    IF v_below_minimum_action = 'convert_remaining_to_standalone' THEN
      v_remaining_store_id := v_remaining_store_ids[1];
      SELECT store_name, vcode
      INTO v_remaining_store_name, v_remaining_store_vcode
      FROM public.stores WHERE id = v_remaining_store_id;

      FOR v_pl IN (
        SELECT pl.*, a.group_id
        FROM public.plantilla pl
        JOIN public.accounts a ON a.id = pl.account_id
        WHERE pl.coverage_group_id = p_request.target_coverage_group_id
          AND pl.status = 'Active'
          AND pl.is_deleted = false
          AND pl.is_archived = false
      ) LOOP
        UPDATE public.plantilla
        SET deployment_type   = 'Stationary',
            coverage_group_id = NULL,
            coverage_slot_id  = NULL,
            store_id          = v_remaining_store_id,
            store_name        = v_remaining_store_name,
            vcode             = v_remaining_store_vcode
        WHERE id = v_pl.id;

        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          UPDATE public.employee_store_allocations
          SET is_active = false, effective_end = CURRENT_DATE
          WHERE plantilla_id = v_pl.id AND is_active = true;

          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          ) VALUES (
            v_pl.id, v_pl.employee_no, NULL,
            v_remaining_store_id, v_remaining_store_vcode, v_remaining_store_name,
            v_pl.account_id, v_pl.group_id,
            1.0, 1,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, p_actor_id
          );
        ELSE
          UPDATE public.plantilla_store_links
          SET status = 'Resigned', deleted_at = now()
          WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;
        END IF;
      END LOOP;

      UPDATE public.coverage_group_stores
      SET archived_at = now(), archived_by = p_actor_id
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = v_remaining_store_id
        AND archived_at IS NULL;

      UPDATE public.coverage_slots
      SET slot_status = 'closed', updated_at = now()
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND slot_status <> 'closed';

      UPDATE public.coverage_groups
      SET archived_at    = now(),
          archived_by    = p_actor_id,
          archive_reason = 'Coverage Request execution: converted remaining store to standalone'
      WHERE id = p_request.target_coverage_group_id;

      v_group_archived := true;
      v_notes := v_notes || ARRAY['remaining store converted to standalone; group archived'];
    END IF;

    -- Archive removed store edges + employee sync
    IF NOT v_group_archived THEN
      UPDATE public.coverage_group_stores
      SET archived_at = now(), archived_by = p_actor_id
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = ANY (v_removed_store_ids)
        AND archived_at IS NULL;

      GET DIAGNOSTICS v_stores_removed = ROW_COUNT;

      FOR v_pl IN (
        SELECT * FROM public.plantilla
        WHERE coverage_group_id = p_request.target_coverage_group_id
          AND status = 'Active'
          AND is_deleted = false
          AND is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          UPDATE public.employee_store_allocations
          SET is_active = false, effective_end = CURRENT_DATE
          WHERE plantilla_id = v_pl.id
            AND store_id = ANY (v_removed_store_ids)
            AND is_active = true;

          SELECT COUNT(*) INTO v_active_allocs
          FROM public.employee_store_allocations
          WHERE plantilla_id = v_pl.id AND is_active = true;

          IF v_active_allocs > 0 THEN
            UPDATE public.employee_store_allocations
            SET active_store_count = v_active_allocs,
                filled_hc = round(1.0 / v_active_allocs, 4)
            WHERE plantilla_id = v_pl.id AND is_active = true;
          END IF;
        ELSE
          UPDATE public.plantilla_store_links psl
          SET status = 'Resigned', deleted_at = now(), unlinked_at = now(), unlinked_by = p_actor_id
          FROM public.stores s
          WHERE psl.vcode = s.vcode
            AND psl.plantilla_id = v_pl.id
            AND s.id = ANY(v_removed_store_ids)
            AND psl.deleted_at IS NULL;
        END IF;
      END LOOP;
    END IF;

    -- Vacancy Slot Reopening for each removed store
    FOREACH v_store_id IN ARRAY v_removed_store_ids LOOP
      SELECT
        s.store_name,
        s.vcode,
        s.account_id,
        s.group_id,
        a.account_name,
        COALESCE(s.area_city, s.area_province, '') AS area_name
      INTO
        v_store_name_local,
        v_store_vcode,
        v_store_account_id,
        v_store_group_id,
        v_store_account_name,
        v_store_area
      FROM public.stores s
      LEFT JOIN public.accounts a ON a.id = s.account_id
      WHERE s.id = v_store_id;

      v_store_group_id := COALESCE(v_store_group_id, v_cg_account_group_id);
      v_store_province_id := NULL;

      IF v_store_vcode IS NULL THEN
        v_notes := v_notes || ARRAY['store ' || v_store_id::text || ' has no vcode; vacancy not created'];
        CONTINUE;
      END IF;

      SELECT
        COALESCE(pl.position, 'Unknown'),
        pl.position_id,
        pl.chain_id
      INTO
        v_store_position,
        v_store_position_id,
        v_store_chain_id
      FROM public.plantilla pl
      WHERE pl.coverage_group_id = p_request.target_coverage_group_id
        AND pl.is_deleted = false
        AND pl.is_archived = false
      LIMIT 1;

      IF v_store_position IS NULL OR v_store_position = 'Unknown' THEN
        v_store_position    := COALESCE(v_cg_position_name, 'Unknown');
        v_store_position_id := COALESCE(v_store_position_id, v_cg_position_id);
      END IF;

      -- Hard guard for position_id validity
      IF NOT EXISTS (
        SELECT 1 FROM public.positions WHERE id = v_store_position_id
      ) THEN
        RAISE EXCEPTION 'Invalid position_id: %', v_store_position_id;
      END IF;

      v_store_employment_type := 'Stationary';

      UPDATE public.vacancies
      SET status              = 'Open',
          is_archived         = false,
          archived_at         = NULL,
          has_pending_closure = false,
          vacant_date         = CURRENT_DATE,
          updated_at          = now()
      WHERE vcode      = v_store_vcode
        AND deleted_at IS NULL
        AND status NOT IN ('Open', 'Pipeline');

      GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

      IF v_rows_updated = 0 THEN
        INSERT INTO public.vacancies (
          vcode, account, position,
          account_id, chain_id, store_id,
          province_id, area_name, position_id,
          vacant_date, vacancy_type, status,
          source_plantilla_id, store_name,
          created_at, updated_at, required_headcount
        )
        SELECT
          v_store_vcode,
          COALESCE(v_store_account_name, 'UNKNOWN'),
          p.position_name,
          v_store_account_id,
          v_store_chain_id,
          v_store_id,
          v_store_province_id,
          v_store_area,
          p.id,
          CURRENT_DATE,
          'Backfill',
          'Open',
          NULL,
          v_store_name_local,
          now(), now(), 1
        FROM public.positions p
        WHERE p.id = v_store_position_id
        ON CONFLICT DO NOTHING;
      END IF;

      SELECT id INTO v_existing_slot_id
      FROM public.plantilla_slots
      WHERE store_id   = v_store_id
        AND account_id = v_store_account_id
        AND slot_status <> 'closed'
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_existing_slot_id IS NOT NULL THEN
        -- ohm#7k2d9f4a: slot_status change routed through fn_set_slot_status;
        -- structural (non-status) columns remain a direct write below.
        v_slot_auth := public.fn_set_slot_status(
          p_slot_id      => v_existing_slot_id,
          p_new_status   => 'open',
          p_reason_code  => 'COVERAGE_STORE_REMOVED',
          p_performed_by => p_actor_id,
          p_remarks      => 'Coverage Request: slot returned to stationary open state.'
        );
        IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
          RAISE EXCEPTION 'coverage request: slot % reopen blocked: %',
            v_existing_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
            USING ERRCODE = '22023';
        END IF;
        UPDATE public.plantilla_slots
        SET employment_type               = 'Stationary',
            is_roving                     = false, -- Bug Fix: reset to false when converted back to stationary
            group_id                      = COALESCE(group_id, v_store_group_id),
            current_occupant_plantilla_id  = NULL,
            closed_at                      = NULL,
            closed_by                      = NULL,
            closure_reason_code            = NULL,
            updated_at                     = now(),
            updated_by                     = p_actor_id
        WHERE id = v_existing_slot_id;

        v_new_slot_id := v_existing_slot_id;
      ELSE
        SELECT id INTO v_existing_slot_id
        FROM public.plantilla_slots
        WHERE store_id   = v_store_id
          AND account_id = v_store_account_id
          AND slot_status = 'closed'
        ORDER BY updated_at DESC
        LIMIT 1;

        IF v_existing_slot_id IS NOT NULL THEN
          -- ohm#7k2d9f4a: slot_status change routed through fn_set_slot_status;
          -- structural (non-status) columns remain a direct write below.
          v_slot_auth := public.fn_set_slot_status(
            p_slot_id      => v_existing_slot_id,
            p_new_status   => 'open',
            p_reason_code  => 'COVERAGE_STORE_REMOVED',
            p_performed_by => p_actor_id,
            p_remarks      => 'Coverage Request: slot returned to stationary open state.'
          );
          IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
            RAISE EXCEPTION 'coverage request: slot % reopen blocked: %',
              v_existing_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
              USING ERRCODE = '22023';
          END IF;
          UPDATE public.plantilla_slots
          SET employment_type               = 'Stationary',
              is_roving                     = false, -- Bug Fix: reset to false when converted back to stationary
              group_id                      = COALESCE(group_id, v_store_group_id),
              current_occupant_plantilla_id  = NULL,
              closed_at                      = NULL,
              closed_by                      = NULL,
              closure_reason_code            = NULL,
              legacy_vcode                   = COALESCE(legacy_vcode, v_store_vcode),
              updated_at                     = now(),
              updated_by                     = p_actor_id
          WHERE id = v_existing_slot_id;

          v_new_slot_id := v_existing_slot_id;
        ELSE
          v_new_slot_id := gen_random_uuid();
          INSERT INTO public.plantilla_slots (
            id, store_id, account_id, group_id,
            position, employment_type, is_roving,
            slot_status, legacy_vcode,
            created_by, updated_by, created_at, updated_at
          ) VALUES (
            v_new_slot_id,
            v_store_id, v_store_account_id, v_store_group_id,
            COALESCE(v_store_position, 'Unknown'),
            'Stationary',
            false,
            'open',
            v_store_vcode,
            p_actor_id, p_actor_id, now(), now()
          );
        END IF;
      END IF;

      INSERT INTO public.slot_history (
        slot_id, account_id, action_type,
        old_value, new_value, reason_code,
        performed_by, remarks, created_at
      ) VALUES (
        v_new_slot_id,
        v_store_account_id,
        'coverage_store_removed',
        'occupied_or_closed',
        'open',
        'COVERAGE_STORE_REMOVED',
        p_actor_id,
        'Coverage Request: store removed from group. Request approved by ' || p_actor_name || '.',
        now()
      );

      v_stores_removed := v_stores_removed + 1;
      v_notes := v_notes || ARRAY[
        'store_removed:' || COALESCE(v_store_name_local, v_store_id::text)
        || '|vcode:' || v_store_vcode
        || '|account:' || COALESCE(v_store_account_name, '')
      ];
    END LOOP;

    IF NOT v_group_archived THEN
      SELECT COUNT(*) INTO v_stores_removed
      FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = ANY (v_removed_store_ids)
        AND archived_at >= now() - interval '10 seconds';
    ELSE
      v_stores_removed := array_length(v_removed_store_ids, 1);
    END IF;

    RETURN jsonb_build_object(
      'structural_execution_enabled',  true,
      'request_type',                  p_request.request_type,
      'stores_added',                  v_stores_added,
      'stores_removed',                v_stores_removed,
      'removed_store_ids',             to_jsonb(v_removed_store_ids),
      'remaining_store_ids',           to_jsonb(v_remaining_store_ids),
      'remaining_count',               v_remaining_count,
      'group_archived',                v_group_archived,
      'anchor_removed',                v_anchor_removed,
      'below_minimum_action_applied',  v_below_minimum_action,
      'notes',                         to_jsonb(v_notes)
    );


  -- ════════════════════════════════════════════════════════════════════════════
  -- ── dissolve_coverage_group ─────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'dissolve_coverage_group'::public.request_type THEN

    -- Pre-resolve group/position
    SELECT a.group_id
    INTO v_cg_account_group_id
    FROM public.coverage_groups cg
    JOIN public.accounts a ON a.id = cg.account_id
    WHERE cg.id = p_request.target_coverage_group_id;

    SELECT pos.position_name, cg.position_id
    INTO v_cg_position_name, v_cg_position_id
    FROM public.coverage_groups cg
    LEFT JOIN public.positions pos ON pos.id = cg.position_id
    WHERE cg.id = p_request.target_coverage_group_id;

    v_employee_home_stores := COALESCE(
      p_request.payload -> 'employee_home_stores',
      '{}'::jsonb
    );

    -- require home store for every active employee
    FOR v_pl IN (
      SELECT pl.*, a.group_id
      FROM public.plantilla pl
      JOIN public.accounts a ON a.id = pl.account_id
      WHERE pl.coverage_group_id = p_request.target_coverage_group_id
        AND pl.status = 'Active'
        AND pl.is_deleted = false
        AND pl.is_archived = false
    ) LOOP
      IF (v_employee_home_stores ->> v_pl.id::text) IS NULL THEN
        RAISE EXCEPTION
          'Dissolve blocked: no retained home store selected for employee % (%). '
          'Select a home store for every active employee before dissolving.',
          COALESCE(v_pl.employee_name, ''), COALESCE(v_pl.employee_no, '')
          USING ERRCODE = '23514';
      END IF;
    END LOOP;

    -- Collect the set of retained store IDs
    SELECT COALESCE(array_agg(DISTINCT val::uuid), ARRAY[]::uuid[])
    INTO v_retained_store_ids
    FROM jsonb_each_text(v_employee_home_stores) AS t(key, val);

    -- Validate retained home stores are active members
    IF v_retained_store_ids IS NOT NULL AND array_length(v_retained_store_ids, 1) > 0 THEN
      IF EXISTS (
        SELECT 1 FROM unnest(v_retained_store_ids) AS rid
        WHERE NOT EXISTS (
          SELECT 1 FROM public.coverage_group_stores
          WHERE coverage_group_id = p_request.target_coverage_group_id
            AND store_id = rid
            AND archived_at IS NULL
        )
      ) THEN
        RAISE EXCEPTION
          'Dissolve blocked: one or more retained home stores are not active members of this coverage group.'
          USING ERRCODE = '23514';
      END IF;
    END IF;

    -- Compute stores losing coverage
    SELECT COALESCE(array_agg(cgs.store_id), ARRAY[]::uuid[])
    INTO v_dissolved_store_ids
    FROM public.coverage_group_stores cgs
    WHERE cgs.coverage_group_id = p_request.target_coverage_group_id
      AND cgs.archived_at IS NULL
      AND NOT (cgs.store_id = ANY(COALESCE(v_retained_store_ids, ARRAY[]::uuid[])));

    -- Convert employee to Stationary
    FOR v_pl IN (
      SELECT pl.*, a.group_id
      FROM public.plantilla pl
      JOIN public.accounts a ON a.id = pl.account_id
      WHERE pl.coverage_group_id = p_request.target_coverage_group_id
        AND pl.status = 'Active'
        AND pl.is_deleted = false
        AND pl.is_archived = false
    ) LOOP
      v_remaining_store_id := (v_employee_home_stores ->> v_pl.id::text)::uuid;

      SELECT s.store_name, s.vcode
      INTO v_remaining_store_name, v_remaining_store_vcode
      FROM public.stores s WHERE s.id = v_remaining_store_id;

      UPDATE public.plantilla
      SET deployment_type   = 'Stationary',
          coverage_group_id = NULL,
          coverage_slot_id  = NULL,
          store_id          = v_remaining_store_id,
          store_name        = v_remaining_store_name,
          vcode             = v_remaining_store_vcode
      WHERE id = v_pl.id;

      IF v_pl.source_employee_import_batch_id IS NOT NULL
        OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        UPDATE public.employee_store_allocations
        SET is_active = false, effective_end = CURRENT_DATE
        WHERE plantilla_id = v_pl.id
          AND is_active = true
          AND store_id <> v_remaining_store_id;

        IF NOT EXISTS (
          SELECT 1 FROM public.employee_store_allocations
          WHERE plantilla_id = v_pl.id
            AND store_id = v_remaining_store_id
            AND is_active = true
        ) THEN
          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          ) VALUES (
            v_pl.id, v_pl.employee_no, NULL,
            v_remaining_store_id, v_remaining_store_vcode, v_remaining_store_name,
            v_pl.account_id, v_pl.group_id,
            1.0, 1,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, p_actor_id
          );
        ELSE
          UPDATE public.employee_store_allocations
          SET roving_group_id    = NULL,
              active_store_count = 1,
              filled_hc          = 1.0
          WHERE plantilla_id = v_pl.id
            AND store_id = v_remaining_store_id
            AND is_active = true;
        END IF;
      ELSE
        UPDATE public.plantilla_store_links psl
        SET status = 'Resigned', deleted_at = now(), unlinked_at = now(), unlinked_by = p_actor_id
        FROM public.stores s
        WHERE psl.vcode = s.vcode
          AND psl.plantilla_id = v_pl.id
          AND s.id <> v_remaining_store_id
          AND psl.deleted_at IS NULL;
      END IF;

      v_employees_converted := v_employees_converted + 1;
      v_notes := v_notes || ARRAY[
        'employee:' || COALESCE(v_pl.employee_name, v_pl.employee_no, v_pl.id::text)
        || '|converted_to_stationary_at:' || COALESCE(v_remaining_store_name, v_remaining_store_id::text)
      ];
    END LOOP;

    -- Archive group store edges
    UPDATE public.coverage_group_stores
    SET archived_at = now(), archived_by = p_actor_id
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND archived_at IS NULL;

    -- Close slots
    UPDATE public.coverage_slots
    SET slot_status = 'closed', updated_at = now()
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND slot_status <> 'closed';

    -- Archive group
    UPDATE public.coverage_groups
    SET archived_at    = now(),
        archived_by    = p_actor_id,
        archive_reason = 'Coverage Request execution: dissolved — employees converted to Stationary'
    WHERE id = p_request.target_coverage_group_id;

    v_group_archived := true;

    -- Reopen vacancies for stores that lost coverage
    IF v_dissolved_store_ids IS NOT NULL
      AND array_length(v_dissolved_store_ids, 1) > 0
    THEN
      FOREACH v_store_id IN ARRAY v_dissolved_store_ids LOOP
        SELECT
          s.store_name,
          s.vcode,
          s.account_id,
          s.group_id,
          a.account_name,
          COALESCE(s.area_city, s.area_province, '') AS area_name
        INTO
          v_store_name_local,
          v_store_vcode,
          v_store_account_id,
          v_store_group_id,
          v_store_account_name,
          v_store_area
        FROM public.stores s
        LEFT JOIN public.accounts a ON a.id = s.account_id
        WHERE s.id = v_store_id;

        v_store_group_id    := COALESCE(v_store_group_id, v_cg_account_group_id);
        v_store_province_id := NULL;
        v_store_chain_id    := NULL;

        IF v_store_vcode IS NULL THEN
          v_notes := v_notes || ARRAY['store ' || v_store_id::text || ' has no vcode; vacancy not created'];
          CONTINUE;
        END IF;

        v_store_position    := COALESCE(v_cg_position_name, 'Unknown');
        v_store_position_id := v_cg_position_id;

        -- Hard guard for position_id validity
        IF NOT EXISTS (
          SELECT 1 FROM public.positions WHERE id = v_store_position_id
        ) THEN
          RAISE EXCEPTION 'Invalid position_id: %', v_store_position_id;
        END IF;

        v_store_employment_type := 'Stationary';

        UPDATE public.vacancies
        SET status              = 'Open',
            is_archived         = false,
            archived_at         = NULL,
            has_pending_closure = false,
            vacant_date         = CURRENT_DATE,
            updated_at          = now()
        WHERE vcode      = v_store_vcode
          AND deleted_at IS NULL
          AND status IN ('Filled', 'Closed', 'Archived', 'Open');

        GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

        IF v_rows_updated = 0 THEN
          INSERT INTO public.vacancies (
            vcode, account, position,
            account_id, chain_id, store_id,
            province_id, area_name, position_id,
            vacant_date, vacancy_type, status,
            source_plantilla_id, store_name,
            created_at, updated_at, required_headcount
          )
          SELECT
            v_store_vcode,
            COALESCE(v_store_account_name, 'UNKNOWN'),
            p.position_name,
            v_store_account_id,
            v_store_chain_id,
            v_store_id,
            v_store_province_id,
            v_store_area,
            p.id,
            CURRENT_DATE,
            'Backfill',
            'Open',
            NULL,
            v_store_name_local,
            now(), now(), 1
          FROM public.positions p
          WHERE p.id = v_store_position_id
          ON CONFLICT DO NOTHING;
        END IF;

        SELECT id INTO v_existing_slot_id
        FROM public.plantilla_slots
        WHERE store_id   = v_store_id
          AND account_id = v_store_account_id
          AND slot_status <> 'closed'
        ORDER BY created_at DESC
        LIMIT 1;

        IF v_existing_slot_id IS NOT NULL THEN
          -- ohm#7k2d9f4a: slot_status change routed through fn_set_slot_status;
          -- structural (non-status) columns remain a direct write below.
          v_slot_auth := public.fn_set_slot_status(
            p_slot_id      => v_existing_slot_id,
            p_new_status   => 'open',
            p_reason_code  => 'COVERAGE_STORE_REMOVED',
            p_performed_by => p_actor_id,
            p_remarks      => 'Coverage Request: slot returned to stationary open state.'
          );
          IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
            RAISE EXCEPTION 'coverage request: slot % reopen blocked: %',
              v_existing_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
              USING ERRCODE = '22023';
          END IF;
          UPDATE public.plantilla_slots
          SET employment_type               = 'Stationary',
              is_roving                     = false, -- Bug Fix: reset to false when converted back to stationary
              group_id                      = COALESCE(group_id, v_store_group_id),
              current_occupant_plantilla_id  = NULL,
              closed_at                      = NULL,
              closed_by                      = NULL,
              closure_reason_code            = NULL,
              updated_at                     = now(),
              updated_by                     = p_actor_id
          WHERE id = v_existing_slot_id;

          v_new_slot_id := v_existing_slot_id;
        ELSE
          SELECT id INTO v_existing_slot_id
          FROM public.plantilla_slots
          WHERE store_id   = v_store_id
            AND account_id = v_store_account_id
            AND slot_status = 'closed'
          ORDER BY updated_at DESC
          LIMIT 1;

          IF v_existing_slot_id IS NOT NULL THEN
            -- ohm#7k2d9f4a: slot_status change routed through fn_set_slot_status;
            -- structural (non-status) columns remain a direct write below.
            v_slot_auth := public.fn_set_slot_status(
              p_slot_id      => v_existing_slot_id,
              p_new_status   => 'open',
              p_reason_code  => 'COVERAGE_STORE_REMOVED',
              p_performed_by => p_actor_id,
              p_remarks      => 'Coverage Request: slot returned to stationary open state.'
            );
            IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
              RAISE EXCEPTION 'coverage request: slot % reopen blocked: %',
                v_existing_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
                USING ERRCODE = '22023';
            END IF;
            UPDATE public.plantilla_slots
            SET employment_type               = 'Stationary',
                is_roving                     = false, -- Bug Fix: reset to false when converted back to stationary
                group_id                      = COALESCE(group_id, v_store_group_id),
                current_occupant_plantilla_id  = NULL,
                closed_at                      = NULL,
                closed_by                      = NULL,
                closure_reason_code            = NULL,
                legacy_vcode                   = COALESCE(legacy_vcode, v_store_vcode),
                updated_at                     = now(),
                updated_by                     = p_actor_id
            WHERE id = v_existing_slot_id;

            v_new_slot_id := v_existing_slot_id;
          ELSE
            v_new_slot_id := gen_random_uuid();
            INSERT INTO public.plantilla_slots (
              id, store_id, account_id, group_id,
              position, employment_type, is_roving,
              slot_status, legacy_vcode,
              created_by, updated_by, created_at, updated_at
            ) VALUES (
              v_new_slot_id,
              v_store_id, v_store_account_id, v_store_group_id,
              COALESCE(v_store_position, 'Unknown'),
              'Stationary',
              false,
              'open',
              v_store_vcode,
              p_actor_id, p_actor_id, now(), now()
            );
          END IF;
        END IF;

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type,
          old_value, new_value, reason_code,
          performed_by, remarks, created_at
        ) VALUES (
          v_new_slot_id,
          v_store_account_id,
          'coverage_store_removed',
          'occupied_or_closed',
          'open',
          'COVERAGE_STORE_REMOVED',
          p_actor_id,
          'Coverage Request dissolve: store removed from group. Request approved by ' || p_actor_name || '.',
          now()
        );

        v_vacancies_reopened := v_vacancies_reopened + 1;
        v_notes := v_notes || ARRAY[
          'store_dissolved:' || COALESCE(v_store_name_local, v_store_id::text)
          || '|vcode:' || v_store_vcode
          || '|account:' || COALESCE(v_store_account_name, '')
        ];
      END LOOP;
    END IF;

    RETURN jsonb_build_object(
      'structural_execution_enabled',  true,
      'request_type',                  'dissolve_coverage_group',
      'stores_added',                  0,
      'stores_removed',                v_vacancies_reopened,
      'group_archived',                true,
      'below_minimum_action_applied',  null,
      'vacancies_reopened',           v_vacancies_reopened,
      'notes',                         to_jsonb(v_notes)
    );

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── convert_stationary_to_roving ────────────────════════════════════════════
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'convert_stationary_to_roving'::public.request_type THEN
    RAISE EXCEPTION 'convert_stationary_to_roving structural execution not implemented' USING ERRCODE = '0A000';

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── merge_coverage_groups ───────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'merge_coverage_groups'::public.request_type THEN
    v_surviving_cg_id := (p_request.payload ->> 'surviving_coverage_group_id')::uuid;
    v_merged_cg_id    := (p_request.payload ->> 'merged_coverage_group_id')::uuid;

    SELECT coverage_code INTO v_surviving_cg_code
    FROM public.coverage_groups WHERE id = v_surviving_cg_id AND archived_at IS NULL;

    SELECT coverage_code INTO v_merged_cg_code
    FROM public.coverage_groups WHERE id = v_merged_cg_id AND archived_at IS NULL;

    IF v_surviving_cg_code IS NULL OR v_merged_cg_code IS NULL THEN
      RAISE EXCEPTION 'Merge blocked: surviving or merged coverage group not found or archived.' USING ERRCODE = '23514';
    END IF;

    -- Transfer member stores
    UPDATE public.coverage_group_stores
    SET coverage_group_id = v_surviving_cg_id,
        is_anchor          = false
    WHERE coverage_group_id = v_merged_cg_id
      AND archived_at IS NULL;
    GET DIAGNOSTICS v_stores_transferred = ROW_COUNT;

    -- Transfer active employees
    FOR v_pl IN (
      SELECT * FROM public.plantilla
      WHERE coverage_group_id = v_merged_cg_id
        AND status = 'Active'
        AND is_deleted = false
        AND is_archived = false
    ) LOOP
      SELECT COALESCE(MAX(slot_ordinal), 0) + 1 INTO v_slot_ordinal
      FROM public.coverage_slots
      WHERE coverage_group_id = v_surviving_cg_id;

      v_slot_id := gen_random_uuid();

      -- Create slot in surviving group
      INSERT INTO public.coverage_slots (
        id, coverage_group_id, slot_ordinal, slot_status, current_occupant_plantilla_id, created_at, updated_at
      ) VALUES (
        v_slot_id, v_surviving_cg_id, v_slot_ordinal, 'active', v_pl.id, now(), now()
      );

      -- Point employee to surviving group + new slot
      UPDATE public.plantilla
      SET coverage_group_id = v_surviving_cg_id,
          coverage_slot_id  = v_slot_id
      WHERE id = v_pl.id;

      v_employees_transferred := v_employees_transferred + 1;
      v_notes := v_notes || ARRAY[
        'employee:' || COALESCE(v_pl.employee_name, v_pl.employee_no, v_pl.id::text)
        || '|transferred_to_coverage_group:' || v_surviving_cg_code
      ];
    END LOOP;

    -- Close old slots in merged group
    UPDATE public.coverage_slots
    SET slot_status = 'closed', updated_at = now()
    WHERE coverage_group_id = v_merged_cg_id
      AND slot_status <> 'closed';

    -- Archive merged group
    UPDATE public.coverage_groups
    SET archived_at    = now(),
        archived_by    = p_actor_id,
        archive_reason = 'Coverage Request merge: merged into surviving group ' || v_surviving_cg_code
    WHERE id = v_merged_cg_id;

    -- Re-sync all employee store allocations for surviving group's active members
    FOR v_pl IN (
      SELECT * FROM public.plantilla
      WHERE coverage_group_id = v_surviving_cg_id
        AND status = 'Active'
        AND is_deleted = false
        AND is_archived = false
    ) LOOP
      IF v_pl.source_employee_import_batch_id IS NOT NULL
         OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        -- Deactivate old allocations
        UPDATE public.employee_store_allocations
        SET is_active = false, effective_end = CURRENT_DATE
        WHERE plantilla_id = v_pl.id AND is_active = true;

        -- Get list of all member stores now in the surviving group
        SELECT ARRAY_AGG(store_id) INTO v_store_ids
        FROM public.coverage_group_stores
        WHERE coverage_group_id = v_surviving_cg_id AND archived_at IS NULL;

        v_store_count := COALESCE(array_length(v_store_ids, 1), 0);

        -- Insert new allocations for all surviving group stores
        FOREACH v_store_id IN ARRAY v_store_ids LOOP
          SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
          FROM public.stores WHERE id = v_store_id;

          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          ) VALUES (
            v_pl.id, v_pl.employee_no, v_surviving_cg_id,
            v_store_id, v_store_vcode, v_store_name_local,
            v_pl.account_id, v_pl.group_id,
            round(1.0 / v_store_count, 4), v_store_count,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, p_actor_id
          );
        END LOOP;
      ELSE
        -- Live employee: deactivate old store links
        UPDATE public.plantilla_store_links
        SET status = 'Resigned', deleted_at = now(), unlinked_at = now(), unlinked_by = p_actor_id
        WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;

        -- Get list of all member stores now in the surviving group
        SELECT ARRAY_AGG(store_id) INTO v_store_ids
        FROM public.coverage_group_stores
        WHERE coverage_group_id = v_surviving_cg_id AND archived_at IS NULL;

        -- Insert new store links for all surviving group stores
        FOREACH v_store_id IN ARRAY v_store_ids LOOP
          SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
          FROM public.stores WHERE id = v_store_id;

          INSERT INTO public.plantilla_store_links (
            plantilla_id,
            coverage_group_id,
            vcode,
            store_name,
            account,
            status,
            linked_at,
            linked_by,
            created_by,
            updated_by
          ) VALUES (
            v_pl.id,
            v_surviving_cg_id,
            v_store_vcode,
            v_store_name_local,
            (SELECT account_name FROM public.accounts WHERE id = v_pl.account_id),
            'Active',
            now(),
            p_actor_id,
            p_actor_id,
            p_actor_id
          );
        END LOOP;

        PERFORM public.fn_sync_employee_store_allocations(v_pl.employee_no);
      END IF;
    END LOOP;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 'merge_coverage_groups',
      'surviving_coverage_group_id',  v_surviving_cg_id,
      'merged_coverage_group_id',     v_merged_cg_id,
      'stores_transferred',           v_stores_transferred,
      'employees_transferred',        v_employees_transferred,
      'notes',                        to_jsonb(v_notes)
    );

  END IF;

  RETURN jsonb_build_object(
    'structural_execution_enabled', false,
    'error', 'unsupported_request_type'
  );
END;
$function$;

-- --------------------------------------------------------------------------
-- 4. tag_backout - ADR-001 CASE 1 fix (plantilla slot release)
-- --------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.tag_backout(p_id uuid, p_reason text, p_reason_code text DEFAULT NULL::text)
 RETURNS hr_emploc
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old           public.hr_emploc;
  v_new           public.hr_emploc;
  v_actor         uuid := get_my_profile_id();
  v_actor_name    text := get_my_full_name();
  v_vacancy_ids   uuid[] := ARRAY[]::uuid[];
  v_extra_ids     uuid[];
  v_vid           uuid;
  v_audit_payload jsonb;
  v_slot_result   jsonb;
  v_ps            public.plantilla_slots;
  v_ps_candidates integer := 0;
  v_ps_release    jsonb;
BEGIN
  IF NOT (i_am_ops() OR i_have_full_access()) THEN
    RAISE EXCEPTION 'forbidden: Ops role required' USING ERRCODE = '42501';
  END IF;
  IF coalesce(btrim(p_reason),'') = '' THEN
    RAISE EXCEPTION 'backout reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_old FROM hr_emploc WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'hr_emploc % not found', p_id USING ERRCODE = 'P0002';
  END IF;
  IF v_old.status = 'Backout' OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % already backed-out', p_id USING ERRCODE = '22023';
  END IF;

  -- Collect linked vacancy IDs: primary + every covered_stores entry
  IF v_old.vacancy_id IS NOT NULL THEN
    v_vacancy_ids := array_append(v_vacancy_ids, v_old.vacancy_id);
  END IF;

  IF v_old.covered_stores IS NOT NULL
     AND jsonb_typeof(v_old.covered_stores) = 'array'
     AND jsonb_array_length(v_old.covered_stores) > 0 THEN
    SELECT array_agg(DISTINCT (e->>'vacancy_id')::uuid)
      INTO v_extra_ids
      FROM jsonb_array_elements(v_old.covered_stores) e
     WHERE e ? 'vacancy_id'
       AND nullif(e->>'vacancy_id','') IS NOT NULL;

    IF v_extra_ids IS NOT NULL THEN
      v_vacancy_ids := v_vacancy_ids || v_extra_ids;
    END IF;
  END IF;

  -- Mark HR Emploc record: BACKOUT (status) + close (deleted_at) + event fields
  UPDATE hr_emploc
     SET status              = 'Backout',
         hr_status           = 'Rejected',
         backout_date        = current_date,
         backout_at          = now(),
         backout_by          = v_actor,
         backout_details     = p_reason,
         backout_reason_code = coalesce(p_reason_code, backout_reason_code),
         deleted_at          = now(),
         updated_at          = now(),
         updated_by          = v_actor
   WHERE id = p_id
   RETURNING * INTO v_new;

  -- Reopen each linked vacancy WITHOUT touching vacant_date (SLA continues)
  FOREACH v_vid IN ARRAY v_vacancy_ids LOOP
    IF v_vid IS NOT NULL THEN
      UPDATE vacancies
         SET status                 = 'Open',
             closure_request_status = 'None',
             has_pending_closure    = false,
             archived_at            = NULL,
             archived_by            = NULL,
             is_archived            = false,
             updated_at             = now(),
             updated_by             = v_actor
       WHERE id = v_vid
         AND deleted_at IS NULL;
      -- vacant_date intentionally untouched — vacancy was never truly filled
    END IF;
  END LOOP;

  -- Coverage slot reset: return slot to 'open' so it can be re-filled.
  -- Non-fatal — slot reset failure must not roll back the HR Emploc backout.
  IF v_old.coverage_slot_id IS NOT NULL THEN
    BEGIN
      v_slot_result := public.fn_set_coverage_slot_status(
        p_slot_id      => v_old.coverage_slot_id,
        p_new_status   => 'open',
        p_performed_by => v_actor,
        p_remarks      => 'Backout: ' || COALESCE(p_reason, 'No reason provided')
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Coverage slot reset failed for slot %: %',
        v_old.coverage_slot_id, SQLERRM;
    END;
  END IF;

  -- == ohm#7k2d9f4a (ADR-001 audit CASE 1 fix) ==============================
  -- Release the linked PLANTILLA slot in the SAME transaction as the backout.
  -- Resolution order:
  --   1. hr_emploc.slot_id (direct linkage set by import/reservation flows)
  --   2. Unambiguous fallback: exactly ONE 'hr_processing' slot on this vcode
  --      that no other active hr_emploc row claims.
  -- The release goes through fn_set_slot_status (slot authority). A blocked
  -- transition indicates slot-state drift and is FATAL: the whole backout
  -- rolls back so the drift must be resolved first.
  IF v_old.slot_id IS NOT NULL THEN
    SELECT ps.* INTO v_ps
    FROM public.plantilla_slots ps
    WHERE ps.id = v_old.slot_id
    FOR UPDATE;
  END IF;

  IF v_ps.id IS NULL AND v_old.vcode IS NOT NULL THEN
    SELECT count(*) INTO v_ps_candidates
    FROM public.plantilla_slots ps
    WHERE ps.legacy_vcode = v_old.vcode
      AND ps.slot_status  = 'hr_processing'
      AND NOT EXISTS (
        SELECT 1 FROM public.hr_emploc he2
        WHERE he2.slot_id    = ps.id
          AND he2.id        <> p_id
          AND he2.deleted_at IS NULL
      );

    IF v_ps_candidates = 1 THEN
      SELECT ps.* INTO v_ps
      FROM public.plantilla_slots ps
      WHERE ps.legacy_vcode = v_old.vcode
        AND ps.slot_status  = 'hr_processing'
        AND NOT EXISTS (
          SELECT 1 FROM public.hr_emploc he2
          WHERE he2.slot_id    = ps.id
            AND he2.id        <> p_id
            AND he2.deleted_at IS NULL
        )
      FOR UPDATE;
    END IF;
  END IF;

  -- Only attempt release when a linked slot exists in a non-open, non-terminal state
  IF v_ps.id IS NOT NULL
     AND v_ps.slot_status IN ('pipeline', 'hr_processing', 'occupied', 'filled') THEN
    IF v_ps.slot_status IN ('occupied', 'filled')
       AND v_ps.current_occupant_plantilla_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.plantilla p
         WHERE p.id           = v_ps.current_occupant_plantilla_id
           AND p.hr_emploc_id = p_id
       ) THEN
      -- Slot is legitimately held by a DIFFERENT employee - do not release.
      NULL;
    ELSE
      v_ps_release := public.fn_set_slot_status(
        p_slot_id      => v_ps.id,
        p_new_status   => 'open',
        p_reason_code  => 'BACKOUT',
        p_performed_by => v_actor,
        p_remarks      => 'Backout: ' || COALESCE(p_reason, 'No reason provided')
      );
      IF (v_ps_release->>'status') NOT IN ('ok', 'no_op') THEN
        RAISE EXCEPTION
          'tag_backout: plantilla slot % could not be released (%). Slot-state drift detected - resolve slot state before backout.',
          v_ps.id, COALESCE(v_ps_release->>'blocked_reason', 'unknown')
          USING ERRCODE = '22023';
      END IF;
    END IF;
  END IF;

  -- Mirror backout signal onto applicant snapshot (no archive)
  IF v_old.applicant_id IS NOT NULL THEN
    UPDATE applicants
       SET backout_date        = current_date,
           backout_reason      = p_reason,
           backout_reason_code = coalesce(p_reason_code, backout_reason_code),
           backout_details     = p_reason,
           status              = 'Backout',
           updated_at          = now(),
           updated_by          = v_actor
     WHERE id = v_old.applicant_id
       AND is_archived = false;
  END IF;

  -- BACKOUT audit event (rich payload in new_data)
  v_audit_payload := jsonb_build_object(
    'event_type',          'BACKOUT',
    'applicant_id',        v_old.applicant_id,
    'applicant_name',      coalesce(v_old.applicant_name_snapshot, v_old.applicant_name),
    'employee_no',         v_old.employee_no,
    'vcode',               v_old.vcode,
    'account',             v_old.account,
    'account_id',          v_old.account_id,
    'store_id',            v_old.store_id,
    'store_name',          v_old.store_name,
    'position',            v_old.position,
    'assignment_type',     v_old.assignment_type::text,
    'covered_stores',      v_old.covered_stores,
    'restored_vacancy_ids',to_jsonb(v_vacancy_ids),
    'coverage_slot_id',    v_old.coverage_slot_id,
    'coverage_group_id',   v_old.coverage_group_id,
    'slot_reset_to',       CASE WHEN v_old.coverage_slot_id IS NOT NULL
                                THEN 'open' ELSE NULL END,
    'plantilla_slot_id',   v_ps.id,
    'plantilla_slot_release', v_ps_release,
    'reason',              p_reason,
    'reason_code',         p_reason_code,
    'triggered_by',        v_actor,
    'triggered_by_name',   v_actor_name,
    'triggered_at',        now()
  );

  INSERT INTO audit_logs(action, module, record_id, actor_id, role, old_data, new_data)
  VALUES ('BACKOUT'::audit_action, 'hr_emploc', p_id, v_actor, get_my_role(),
          to_jsonb(v_old), v_audit_payload);

  RETURN v_new;
END
$function$;

-- --------------------------------------------------------------------------
-- 5. Grant lockdown - assert no direct UPDATE on plantilla_slots for
--    anon/authenticated (guarded, idempotent; service_role and postgres
--    grants untouched)
-- --------------------------------------------------------------------------

DO $lockdown$
DECLARE
  r record;
BEGIN
  -- Whole-table UPDATE revocation (safe no-op when the grant is absent)
  IF EXISTS (
    SELECT 1
    FROM information_schema.role_table_grants
    WHERE table_schema   = 'public'
      AND table_name     = 'plantilla_slots'
      AND grantee        IN ('anon', 'authenticated')
      AND privilege_type = 'UPDATE'
  ) THEN
    REVOKE UPDATE ON TABLE public.plantilla_slots FROM anon, authenticated;
  END IF;

  -- Column-level UPDATE revocation (a table-level revoke does not clear
  -- column-level grants, so these are revoked explicitly)
  FOR r IN
    SELECT DISTINCT grantee, column_name
    FROM information_schema.column_privileges
    WHERE table_schema   = 'public'
      AND table_name     = 'plantilla_slots'
      AND grantee        IN ('anon', 'authenticated')
      AND privilege_type = 'UPDATE'
  LOOP
    EXECUTE format(
      'REVOKE UPDATE (%I) ON TABLE public.plantilla_slots FROM %I',
      r.column_name, r.grantee
    );
  END LOOP;
END
$lockdown$;
