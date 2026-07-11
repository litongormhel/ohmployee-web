-- ============================================================
-- OHM2026_0021 — Phase 6.3: Wire HR Processing → Occupied Slot Transition
-- Migration: 20260813000003_wire_hr_processing_occupied_slot_transition.sql
-- Depends on: 20260812000000_fn_set_slot_status.sql      (Phase 6.0 — fn_set_slot_status)
--             20260813000001_wire_open_pipeline_slot_transitions.sql
--               (Phase 6.1 — fn_sync_vacancy_slot_open_pipeline)
--             20260813000002_wire_pipeline_hr_processing_slot_transition.sql
--               (Phase 6.2 — fn_sync_slot_to_hr_processing)
--             20260521200000_vcode_duplicate_cleanup.sql
--               (move_to_plantilla — latest live version; stationary + roving + pool paths)
-- ============================================================
-- Phase 6.3 of slot_lifecycle_automation_plan.md (OHM2026_0017).
--
-- SCOPE: Wire the hr_processing → occupied slot transition (+ occupant link)
-- into move_to_plantilla, which is the only RPC that creates the plantilla row
-- and finalises the HR Emploc → Plantilla movement. No other workflow,
-- vacancy/applicant behavior, HR Emploc behavior, UI, or migration is changed.
--
-- Hook point:
--   move_to_plantilla — in the common tail, after both audit log PERFORMs
--   and before the final RETURN v_pl. The hook is guarded with
--   IF NOT v_is_pool AND v_emp.assignment_type <> 'Roving' so only the
--   stationary path ever triggers it.
--
-- Slot lookup: plantilla_slots.legacy_vcode = v_emp.vcode (1:1 bridge,
--   per OHM2026_0017 Q6), non-roving only. Relies on the partial-unique
--   index on legacy_vcode (20260807000000_plantilla_slots_legacy_vcode_link.sql).
--
-- Occupant assignment:
--   p_occupant_plantilla_id = v_pl.id (the newly-created plantilla row).
--   fn_set_slot_status sets current_occupant_plantilla_id on the slot row
--   and validates the occupant is non-NULL (required invariant for into-occupied).
--
-- Reason code: REPLACEMENT
--   Matches the task specification (OHM2026_0021). Records that the slot is
--   being filled — whether this is the first occupant ever or a refill after
--   a previous occupant separated.
--
-- Non-blocking contract (hard requirement — OHM2026_0017 Q1):
--   A slot sync error must NEVER roll back or alter move_to_plantilla's
--   transaction. fn_sync_slot_to_occupied (§1) catches ALL exceptions
--   internally and emits RAISE NOTICE only.
--
-- Roving / pool carve-out:
--   Roving (assignment_type = 'Roving' or is_roving = true):
--     No reliable 1:1 VCODE→slot mapping until the deferred coverage model
--     lands (OHM2026_0017 Q6). Skipped unconditionally at two levels:
--     (a) host RPC guard (IF NOT v_is_pool AND v_emp.assignment_type <> 'Roving');
--     (b) helper also filters is_roving = false on the slot lookup.
--   Pool (v_is_pool = true):
--     Pool slots are managed via workforce_pool_slots, not plantilla_slots.
--     Pool path is excluded by the same host RPC guard.
--
-- Sections:
--   §1  fn_sync_slot_to_occupied   (internal non-blocking helper)
--   §2  Patch move_to_plantilla    (Phase 6.3 slot sync hook added)
--   §3  GRANT
-- ============================================================


-- ============================================================
-- §1  fn_sync_slot_to_occupied
-- ============================================================
-- Non-blocking internal helper that transitions a vacancy slot from
-- hr_processing to occupied after move_to_plantilla succeeds on the
-- stationary (non-roving, non-pool) path.
--
-- Called AFTER the host RPC has written the plantilla row and both audit
-- log entries — the transition represents confirmed, committed state.
--
-- Arguments
-- ---------
--   p_vcode        — Vacancy VCODE (hr_emploc.vcode).
--   p_hr_emploc_id — HR Emploc UUID; written to slot_history.remarks.
--   p_plantilla_id — Newly-created plantilla.id; passed as occupant link.
--   p_performed_by — Acting user UUID for slot_history.performed_by.
--   p_source_fn    — Calling function name; written to slot_history.remarks.
--
-- Returns: JSONB from fn_set_slot_status (ok / no_op / blocked), or NULL
--          when skipped (no slot, null vcode/plantilla_id, roving, any error).
-- NEVER RAISES.

CREATE OR REPLACE FUNCTION public.fn_sync_slot_to_occupied(
  p_vcode        text,
  p_hr_emploc_id uuid DEFAULT NULL,
  p_plantilla_id uuid DEFAULT NULL,
  p_performed_by uuid DEFAULT NULL,
  p_source_fn    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
/*
  Phase 6.3 — non-blocking hr_processing→occupied slot sync (OHM2026_0021).

  Locates the slot by legacy_vcode (1:1 bridge, non-roving only).
  Delegates to fn_set_slot_status with:
    p_new_status            = 'occupied'
    p_reason_code           = 'REPLACEMENT'  (OHM2026_0021 task spec)
    p_occupant_plantilla_id = p_plantilla_id

  Blocked or no_op results from fn_set_slot_status are logged via
  RAISE NOTICE and returned as-is — they never raise into the host RPC.
*/
DECLARE
  v_slot_id uuid;
  v_result  jsonb;
BEGIN
  -- ── Guard: VCODE required ───────────────────────────────────────────
  IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
    RAISE NOTICE
      'fn_sync_slot_to_occupied: skipped — p_vcode is null/empty (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- ── Guard: plantilla_id required (occupant link invariant) ──────────
  -- into-occupied with NULL occupant is a blocked transition in fn_set_slot_status.
  -- Catch it here first so the skip reason is explicit in the notice log.
  IF p_plantilla_id IS NULL THEN
    RAISE NOTICE
      'fn_sync_slot_to_occupied: skipped — p_plantilla_id is null, '
      'cannot set occupant link (VCODE=%, source=%)',
      p_vcode, COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- ── Locate slot via legacy_vcode bridge ──────────────────────────────
  -- Partial-unique index on legacy_vcode guarantees at most one match.
  -- Roving slots excluded: no reliable 1:1 VCODE→slot until coverage model.
  SELECT id INTO v_slot_id
  FROM public.plantilla_slots
  WHERE legacy_vcode = p_vcode
    AND is_roving = false
  LIMIT 1;

  IF v_slot_id IS NULL THEN
    -- No slot for this VCODE (pre-slot-era legacy vacancy or roving) — skip.
    RETURN NULL;
  END IF;

  -- ── Delegate to central transition helper ────────────────────────────
  -- fn_set_slot_status handles: matrix validation, slot row update
  -- (slot_status + current_occupant_plantilla_id + updated_at/by),
  -- and slot_history append.
  -- Reason code REPLACEMENT is task-specified for Phase 6.3 (OHM2026_0021).
  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => 'occupied',
    p_reason_code           => 'REPLACEMENT',
    p_performed_by          => p_performed_by,
    p_remarks               => format(
                                 'Phase 6.3 / %s / VCODE=%s / hr_emploc_id=%s / plantilla_id=%s',
                                 COALESCE(p_source_fn, 'unknown'),
                                 p_vcode,
                                 COALESCE(p_hr_emploc_id::text, 'null'),
                                 p_plantilla_id::text
                               ),
    p_occupant_plantilla_id => p_plantilla_id
  ) INTO v_result;

  -- Log blocked/no_op outcomes for observability; never raise.
  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_slot_to_occupied: % for slot_id=% VCODE=% plantilla_id=% source=% — %',
      v_result->>'status',
      v_slot_id,
      p_vcode,
      p_plantilla_id,
      COALESCE(p_source_fn, 'unknown'),
      COALESCE(v_result->>'blocked_reason', 'same-state no_op');
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  -- Non-blocking contract: log and skip. Host RPC transaction continues.
  RAISE NOTICE
    'fn_sync_slot_to_occupied: error for VCODE=% plantilla_id=% source=% — % (sqlstate=%)',
    p_vcode, p_plantilla_id, COALESCE(p_source_fn, 'unknown'), SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_sync_slot_to_occupied(text, uuid, uuid, uuid, text) IS
  'Phase 6.3 — non-blocking hr_processing→occupied slot sync helper (OHM2026_0021). '
  'Called after move_to_plantilla succeeds on the stationary (non-roving, non-pool) path. '
  'Locates slot by legacy_vcode (non-roving only), calls fn_set_slot_status with '
  'p_new_status=occupied, p_reason_code=REPLACEMENT, p_occupant_plantilla_id=p_plantilla_id. '
  'NEVER raises. Blocked/no_op results are RAISE NOTICEd and returned. '
  'Callers: move_to_plantilla (stationary non-roving non-pool path only).';


-- ============================================================
-- §2  Patch move_to_plantilla (Phase 6.3 slot sync hook)
-- ============================================================
-- Source: 20260521200000_vcode_duplicate_cleanup.sql
--   (latest version — adds VCODE fallback for vacancy close on all three paths).
-- Change: ONE addition — fn_sync_slot_to_occupied call inserted in the
--         common tail, after both log_audit_event PERFORMs and before
--         the final RETURN v_pl. The hook is guarded with
--         IF NOT v_is_pool AND v_emp.assignment_type <> 'Roving'
--         so roving and pool paths are never touched.
-- All existing behavior — RBAC, idempotency guards, pool path, roving path,
-- stationary path, vacancy close, hr_emploc status update, audit log,
-- return shape, SECURITY DEFINER, GRANT — is preserved IDENTICALLY.
-- No parameter or return type changes.

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

  -- ── Phase 6.3: non-blocking slot hr_processing→occupied sync ─────────────
  -- Wires the HR Emploc → Plantilla transition into the slot lifecycle model.
  -- Only fires for stationary (non-roving, non-pool) employees; roving and pool
  -- slots use different ownership models and are deferred (OHM2026_0017 Q6).
  -- fn_sync_slot_to_occupied NEVER raises; a slot error will not roll back
  -- this function's plantilla creation, vacancy close, hr_emploc update,
  -- or audit log writes.
  IF NOT v_is_pool AND v_emp.assignment_type <> 'Roving' THEN
    PERFORM public.fn_sync_slot_to_occupied(
      p_vcode        => v_emp.vcode,
      p_hr_emploc_id => p_id,
      p_plantilla_id => v_pl.id,
      p_performed_by => v_actor,
      p_source_fn    => 'move_to_plantilla'
    );
  END IF;

  RETURN v_pl;
END
$$;

COMMENT ON FUNCTION public.move_to_plantilla(uuid) IS
  'Moves an HR Emploc record to Plantilla (stationary, roving, or pool path). '
  'Phase 6.3 (OHM2026_0021): also syncs the matching plantilla slot hr_processing→occupied '
  'after both audit log writes, on the stationary non-roving non-pool path only, '
  'via fn_sync_slot_to_occupied (non-blocking). '
  'Roving and pool slots are excluded (carve-outs: no reliable 1:1 VCODE→slot / '
  'pool uses workforce_pool_slots, not plantilla_slots).';


-- ============================================================
-- §3  GRANT
-- ============================================================
-- fn_sync_slot_to_occupied is an internal helper called only from
-- SECURITY DEFINER RPCs; restrict to authenticated.

REVOKE ALL ON FUNCTION public.fn_sync_slot_to_occupied(text, uuid, uuid, uuid, text)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_sync_slot_to_occupied(text, uuid, uuid, uuid, text)
  TO authenticated;

-- Preserve existing GRANTs on move_to_plantilla (unchanged from 20260521200000).
REVOKE ALL ON FUNCTION public.move_to_plantilla(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.move_to_plantilla(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_to_plantilla(uuid) TO service_role;


-- ============================================================
-- Validation Queries (run manually after applying)
-- ============================================================
--
-- V1 — Helper function exists with correct signature
--   SELECT routine_name, routine_type, security_type
--   FROM information_schema.routines
--   WHERE routine_schema = 'public'
--     AND routine_name = 'fn_sync_slot_to_occupied';
--   -- Expected: 1 row, FUNCTION, DEFINER
--
-- V2 — move_to_plantilla body includes Phase 6.3 hook
--   SELECT prosrc LIKE '%fn_sync_slot_to_occupied%'
--   FROM pg_proc
--   WHERE proname = 'move_to_plantilla'
--     AND pronamespace = 'public'::regnamespace;
--   -- Expected: true
--
-- V3 — Slot moves hr_processing → occupied on stationary move_to_plantilla
--   (After moving a stationary HR Emploc record to Plantilla for a VCODE
--    whose slot is currently in hr_processing status)
--   SELECT slot_status, current_occupant_plantilla_id
--   FROM public.plantilla_slots
--   WHERE legacy_vcode = '<test_vcode>';
--   -- Expected: slot_status='occupied', current_occupant_plantilla_id=<plantilla.id>
--
--   SELECT action_type, old_value, new_value, reason_code, remarks
--   FROM public.slot_history
--   WHERE slot_id = (SELECT id FROM public.plantilla_slots WHERE legacy_vcode = '<test_vcode>')
--   ORDER BY created_at DESC LIMIT 5;
--   -- Expected: one row with action_type='occupied', old_value='hr_processing',
--   --           new_value='occupied', reason_code='REPLACEMENT',
--   --           remarks includes 'Phase 6.3 / move_to_plantilla / VCODE=...'
--
-- V4 — current_occupant_plantilla_id matches the new plantilla row
--   SELECT ps.current_occupant_plantilla_id, p.id, p.employee_no, p.status
--   FROM public.plantilla_slots ps
--   JOIN public.plantilla p ON p.id = ps.current_occupant_plantilla_id
--   WHERE ps.legacy_vcode = '<test_vcode>';
--   -- Expected: 1 row with the correct employee_no and status='Active'
--
-- V5 — move_to_plantilla still returns expected plantilla row
--   (Call with a valid stationary HR Emploc record)
--   -- Expected: full plantilla row (RETURNS public.plantilla — shape unchanged)
--
-- V6 — Roving paths NOT touched by Phase 6.3 sync
--   SELECT slot_status, current_occupant_plantilla_id
--   FROM public.plantilla_slots
--   WHERE is_roving = true;
--   -- Status and occupant must match pre-migration snapshot
--   -- (Phase 6.3 never writes roving slots)
--
-- V7 — Pool paths NOT touched by Phase 6.3 sync
--   -- Pool employees use workforce_pool_slots, not plantilla_slots.
--   -- Verify no plantilla_slots row has current_occupant_plantilla_id set
--   -- to a pool employee (is_pool_employee=true).
--   SELECT count(*)
--   FROM public.plantilla_slots ps
--   JOIN public.plantilla p ON p.id = ps.current_occupant_plantilla_id
--   WHERE p.is_pool_employee = true;
--   -- Expected: 0 (pool employees do not occupy plantilla_slots)
--
-- V8 — Occupied slots excluded from vw_slot_derived_vacancy_shadow
--   SELECT count(*) FROM public.vw_slot_derived_vacancy_shadow
--   WHERE slot_status = 'occupied';
--   -- Expected: 0 (view WHERE clause already excludes occupied; verified unchanged)
--
-- V9 — slot_history written only on successful stationary transition
--   SELECT count(*) FROM public.slot_history
--   WHERE remarks LIKE 'Phase 6.3%'
--     AND action_type != 'occupied';
--   -- Expected: 0 (only occupied action_type written by Phase 6.3)
--
-- V10 — REPLACEMENT reason code is valid in slot_reason_codes
--   SELECT code, label FROM public.slot_reason_codes WHERE code = 'REPLACEMENT';
--   -- Expected: 1 row (defined in 20260804000000_plantilla_slot_foundation_v1.sql)
--
-- V11 — P1–P8 reconciliation baseline after Phase 6.3
--   (Re-run the parity suite from OHM2026_0016 / 20260811000000_fix_backfill_parity_d1_d2.sql)
--   NOTE: occupied slots are excluded from the shadow Vacancy view (open+pipeline+closed only).
--   Any slot now in occupied will appear in legacy as Filled (vacancy.status='Filled')
--   and NOT in the shadow view. This is correct expected behavior.
--   Any slot still in hr_processing (no move_to_plantilla yet) appears in legacy as Open
--   (active_applicant_count=0 after Confirmed Onboard) and NOT in shadow — unchanged from Phase 6.2.
-- ============================================================
