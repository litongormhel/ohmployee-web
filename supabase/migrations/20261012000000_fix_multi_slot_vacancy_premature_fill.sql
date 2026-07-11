-- ============================================================================
-- OHM2026_0081 — Fix Multi-Slot Vacancy Premature Filled + Auto-Archive on
--               First Hire (VCAG5_0058 / HC-235E55AF visible fix)
-- Migration: 20261012000000_fix_multi_slot_vacancy_premature_fill.sql
-- Depends on: 20261011000000_fix_duplicate_slot_creation_from_hc_request.sql
-- ============================================================================
--
-- ROOT CAUSE:
--   move_to_plantilla (stationary path) unconditionally set the vacancy
--   status to 'Filled' when moving ANY employee to Plantilla for a given
--   VCODE — regardless of how many slots remained open. For HC=N vacancies
--   (N > 1) this caused:
--
--   1. First hire of N: the stationary path fires:
--        UPDATE vacancies SET status = 'Filled' WHERE id = v_emp.vacancy_id;
--        UPDATE vacancies SET status = 'Filled' WHERE vcode = v_emp.vcode
--           AND status IN ('Open','For Sourcing') ...;   -- VCODE fallback
--      Both UPDATEs ran because fn_sync_slot_to_occupied (which marks the
--      current slot occupied) was called AFTER the vacancy update.  At the
--      moment of the vacancy update the current slot was still 'hr_processing',
--      so there was no way to distinguish "first of three" from "last of three".
--
--   2. BEFORE UPDATE trigger on_vacancy_filled_archive fired on the
--      status → 'Filled' transition → set is_archived = TRUE, archived_at.
--
--   3. vw_slot_derived_vacancy_shadow JOINs vacancies with guard
--        COALESCE(v.is_archived, false) = false AND v.status <> 'Archived'
--      → VCAG5_0058 became invisible to every vacancy-derived surface
--        (Plantilla Required/Vacant, Vacancy tab, shadow view, CENCOM,
--        Dashboard) even though 2 out of 3 slots were still open.
--
--   Observed instance:
--     Request  : HC-235E55AF  (HC=3, ACTISERVE / SM MANDA)
--     VCode    : VCAG5_0058
--     Slots    : 3 created correctly — ordinal 1 occupied, 2+3 open
--     Vacancy  : status='Filled', is_archived=true  ← WRONG at first hire
--     Shadow   : 0 rows (excluded)
--
-- FIX — TWO PARTS:
--
--   §1  move_to_plantilla — pure stationary path (non-pool, non-roving,
--       no coverage_slot_id):
--       a. Call fn_sync_slot_to_occupied BEFORE the vacancy status updates so
--          the current slot's state is 'occupied' at the time of the NOT EXISTS
--          guard evaluation.
--       b. Add NOT EXISTS guard to both the vacancy_id-specific UPDATE and the
--          VCODE fallback UPDATE:
--            AND NOT EXISTS (
--              SELECT 1 FROM public.plantilla_slots ps
--              WHERE ps.legacy_vcode = v_emp.vcode
--                AND ps.is_roving = false
--                AND ps.slot_status IN ('open','pipeline','hr_processing')
--            )
--          Vacancy is marked 'Filled' only when every non-closed slot is
--          occupied. For HC=1 the guard is satisfied immediately; for HC=N
--          it fires only on the N-th hire.
--       c. Remove fn_sync_slot_to_occupied from the final shared block (it is
--          now called inside the stationary sub-path, before the vacancy update).
--       Roving, pool, and CGCODE-coverage paths are NOT changed; their vacancy
--       semantics are different and do not use plantilla_slots as the source.
--
--   §2  One-time data fix: restore VCAG5_0058 to Open / is_archived=false.
--       The on_vacancy_filled_archive BEFORE trigger will NOT re-fire because
--       the UPDATE sets status='Open' (not 'Filled'). The
--       trg_vacancy_archive_reset_cascade AFTER trigger fires on the
--       is_archived change but does nothing (rollback path requires
--       OLD.qa_archive_batch_id IS NOT NULL; VCAG5_0058 was never QA-archived).
--       Applicant ANGEL AQUINO LOCSIN was NOT cascade-archived (the AFTER
--       UPDATE OF is_archived trigger did not fire because is_archived was not
--       in move_to_plantilla's SET clause). No applicant fix needed.
--
-- DELIBERATELY NOT CHANGED:
--   • on_vacancy_filled_archive — correct behavior, fires at the right time
--     after this fix (only when all slots are occupied).
--   • vw_slot_derived_vacancy_shadow — is_archived guard is correct.
--   • Pool / roving / CGCODE paths in move_to_plantilla — unchanged.
--   • OHM2026_0080 cleanup logic — untouched.
--   • fn_sync_slot_to_occupied — unchanged; only call site moves earlier.
--   • No hard deletes. No Flutter / Dart changes.
--
-- VALIDATION (see §3 trailing comments; run after applying).
-- ============================================================================

BEGIN;

-- ============================================================================
-- §1  move_to_plantilla — slot-aware vacancy closure for stationary path
-- ============================================================================

CREATE OR REPLACE FUNCTION public.move_to_plantilla(p_id uuid)
RETURNS public.plantilla
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
/*
  OHM2026_0081: for the pure-stationary path, fn_sync_slot_to_occupied is now
  called BEFORE the vacancy status updates, and both vacancy-closing UPDATEs
  carry a NOT EXISTS slot guard.  Only when all non-closed slots are occupied
  (no open/pipeline/hr_processing remaining) does the vacancy transition to
  'Filled' — preventing premature archival on the first hire of a multi-slot
  vacancy.

  All other paths (pool, roving, CGCODE coverage) are unchanged.
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
      -- ── CGCODE COVERAGE SUB-PATH (unchanged) ─────────────────────────────
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
      -- Only marks Filled (and triggers on_vacancy_filled_archive → is_archived)
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

COMMENT ON FUNCTION public.move_to_plantilla(uuid) IS
  'OHM2026_0081: pure-stationary path now calls fn_sync_slot_to_occupied '
  'BEFORE the vacancy status update, and both vacancy-closing UPDATEs carry '
  'a NOT EXISTS slot guard. Vacancy transitions to Filled only when every '
  'non-closed slot is occupied — preventing premature archival of multi-slot '
  '(HC>1) HC-request vacancies on the first hire. Pool, roving, and CGCODE '
  'coverage paths unchanged.';

REVOKE ALL ON FUNCTION public.move_to_plantilla(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.move_to_plantilla(uuid) TO authenticated;


-- ============================================================================
-- §2  One-time data fix — restore VCAG5_0058 vacancy to Open / is_archived=false
-- ============================================================================
-- VCAG5_0058 was incorrectly set to Filled + is_archived=true when ANGEL
-- AQUINO LOCSIN was moved to Plantilla (slot 1 of 3). Slots 2 and 3 are
-- still 'open'. Restoring to 'Open' + is_archived=false makes the vacancy
-- visible in vw_slot_derived_vacancy_shadow and all downstream surfaces.
--
-- Safety notes:
--   • on_vacancy_filled_archive BEFORE trigger does NOT fire (status → 'Open',
--     not 'Filled').
--   • trg_vacancy_archive_reset_cascade AFTER trigger fires on is_archived
--     change, but the rollback path requires OLD.qa_archive_batch_id IS NOT
--     NULL — VCAG5_0058 was never QA-archived, so qa_archive_batch_id IS NULL
--     and the cascade is a no-op.
--   • The applicant (ANGEL AQUINO LOCSIN) was NOT cascade-archived; no
--     applicant change needed.

DO $$
DECLARE
  v_rows integer;
BEGIN
  UPDATE public.vacancies
     SET status      = 'Open',
         is_archived = false,
         archived_at = NULL,
         archived_by = NULL,
         updated_at  = NOW()
   WHERE vcode       = 'VCAG5_0058'
     AND status      = 'Filled'
     AND COALESCE(is_archived, false) = true;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RAISE NOTICE 'OHM2026_0081 data fix: % vacancy row(s) restored to Open for VCAG5_0058.', v_rows;
END$$;

COMMIT;

-- ============================================================================
-- §3  Post-migration validation (run manually after applying)
-- ============================================================================
--
-- V1 — VCAG5_0058 vacancy: status='Open', is_archived=false.
--   SELECT vcode, status, is_archived, required_headcount
--   FROM public.vacancies
--   WHERE vcode = 'VCAG5_0058';
--   -- Expect: status='Open', is_archived=false, required_headcount=3
--
-- V2 — VCAG5_0058 active slots = 3 (1 occupied, 2 open).
--   SELECT slot_status, COUNT(*)
--   FROM public.plantilla_slots
--   WHERE legacy_vcode = 'VCAG5_0058'
--   GROUP BY slot_status ORDER BY slot_status;
--   -- Expect: occupied=1, open=2 (no closed)
--
-- V3 — Shadow view for VCAG5_0058: visible, required_hc=3, open_count=2, occupied_count=1.
--   SELECT legacy_vcode, required_hc, open_count, occupied_count, vacancy_tab
--   FROM public.vw_slot_derived_vacancy_shadow
--   WHERE legacy_vcode = 'VCAG5_0058';
--   -- Expect: 1 row, required_hc=3, open_count=2, occupied_count=1, vacancy_tab='Open'
--
-- V4 — ACTISERVE slot_vacant_hc includes VCAG5_0058's 2 open slots.
--   SELECT account_id, slot_vacant_hc, required_hc
--   FROM public.v_account_allocation_kpi
--   WHERE account_id = '4fba7c47-f19e-47fb-9074-6acab754721f';
--   -- Expect: slot_vacant_hc >= 2 (includes VCAG5_0058 open slots)
--
-- V5 — VCAG5_0057 (OHM2026_0080 fix) unchanged: 2 active slots.
--   SELECT slot_status, COUNT(*)
--   FROM public.plantilla_slots
--   WHERE legacy_vcode = 'VCAG5_0057'
--   GROUP BY slot_status ORDER BY slot_status;
--   -- Expect: open=2 (closed=2 from OHM2026_0080 cleanup — unchanged)
--
-- V6 — Forward path: moving a second employee to VCAG5_0058 plantilla leaves
--      vacancy status='Open' (1 slot still open).
--   (Manual: confirm_applicant_onboard → move_to_plantilla for slot 2)
--   SELECT vcode, status, is_archived FROM public.vacancies WHERE vcode='VCAG5_0058';
--   -- Expect: status='Open', is_archived=false  (1 slot remaining)
--
-- V7 — Forward path: moving the third (last) employee sets vacancy 'Filled'.
--   (Manual: confirm_applicant_onboard → move_to_plantilla for slot 3)
--   SELECT vcode, status, is_archived FROM public.vacancies WHERE vcode='VCAG5_0058';
--   -- Expect: status='Filled', is_archived=true  (all slots occupied)
--
-- V8 — No idempotency regression: fn_create_slots_from_hc_request re-run
--      creates no new slots (status=completed guard).
--   SELECT public.create_plantilla_slot_from_request(
--            '235e55af-ddde-4651-97e4-80d9a20e90c0'::uuid);
--   -- Expect: ok=false, error='request_not_approved'
-- ============================================================================
