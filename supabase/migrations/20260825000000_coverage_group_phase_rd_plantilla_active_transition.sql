-- ============================================================
-- OHM2026_0080 — Coverage Group Phase R-D: Plantilla Active Transition
-- Migration:  20260825000000_coverage_group_phase_rd_plantilla_active_transition.sql
-- Plan:       docs/architecture/coverage_group_phase_rd_plantilla_active_plan.md (OHM2026_0079)
-- Depends on:
--   20260824000000_coverage_group_phase_rc_hr_emploc_binding.sql
--     (hr_emploc.coverage_slot_id / coverage_group_id source of truth in HR processing;
--      fn_set_coverage_slot_status owns open↔pipeline, pipeline→hr_processing,
--      hr_processing→open; hr_processing→active deliberately refused)
--   20260822000006_coverage_group_ra6_binding_columns.sql
--     (plantilla.coverage_slot_id / coverage_group_id nullable FK columns)
-- ============================================================
-- Scope: Phase R-D — complete the roving move-to-Plantilla hand-off. The
-- exact HR-processing coverage slot becomes active when a Plantilla row is
-- created, and the Plantilla row becomes the deployment-side owner.
--
-- What this migration does:
--   RD1  Add coverage_slots.current_occupant_plantilla_id.
--   RD2  Extend fn_set_coverage_slot_status with p_occupant_plantilla_id and
--        allow exactly one new edge: hr_processing→active. Into-active requires
--        a non-NULL occupant. active→open and closed edges stay refused.
--   RD3  Add uq_plantilla_one_active_per_coverage_slot and the plantilla
--        roving_assignment_id/coverage_slot_id mutex.
--   RD4  Add fn_sync_coverage_slot_to_active, a non-blocking exact-slot wrapper.
--   RD5  Patch move_to_plantilla directly: CGCODE rows enter a coverage
--        sub-branch inside the stationary ELSE block, insert Plantilla with
--        coverage_slot_id + coverage_group_id, then activate the exact slot in
--        the common tail. Stationary occupied behavior remains unchanged.
--
-- What this migration deliberately does NOT do:
--   • Apply itself or push to Supabase
--   • Modify Flutter
--   • Implement separation, transfer, closure, reporting, or roving shadow
--   • Open active→open or any closed transition
--   • Modify the stationary occupied path; rows without coverage_slot_id fall
--     through unchanged and continue to use fn_sync_slot_to_occupied
-- ============================================================


-- ============================================================
-- §RD1 — coverage_slots occupant link
-- ============================================================

ALTER TABLE public.coverage_slots
  ADD COLUMN IF NOT EXISTS current_occupant_plantilla_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conname = 'coverage_slots_current_occupant_plantilla_id_fkey'
  ) THEN
    ALTER TABLE public.coverage_slots
      ADD CONSTRAINT coverage_slots_current_occupant_plantilla_id_fkey
      FOREIGN KEY (current_occupant_plantilla_id)
      REFERENCES public.plantilla(id)
      ON DELETE SET NULL;
  END IF;
END;
$$;

COMMENT ON COLUMN public.coverage_slots.current_occupant_plantilla_id IS
  'Phase R-D (OHM2026_0080): current active Plantilla occupant for a coverage slot. '
  'Set on hr_processing->active; cleared by the later active->open separation seam.';


-- ============================================================
-- §RD2 — Extend fn_set_coverage_slot_status (open only hr_processing→active)
-- ============================================================
-- R-C owned open↔pipeline, pipeline→hr_processing, and hr_processing→open.
-- R-D adds exactly one edge: hr_processing→active. Into-active requires a
-- non-NULL occupant Plantilla id and writes current_occupant_plantilla_id.
-- active→open remains refused for the later separation seam; every closed
-- edge remains refused for the later closure seam.

DROP FUNCTION IF EXISTS public.fn_set_coverage_slot_status(uuid, text, uuid, text);

CREATE OR REPLACE FUNCTION public.fn_set_coverage_slot_status(
  p_slot_id                 uuid,
  p_new_status              text,
  p_performed_by            uuid DEFAULT NULL,
  p_remarks                 text DEFAULT NULL,
  p_occupant_plantilla_id   uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cur text;
  v_ord integer;
BEGIN
  IF p_slot_id IS NULL THEN
    RETURN jsonb_build_object('status', 'no_op', 'reason', 'null_slot');
  END IF;

  SELECT slot_status, slot_ordinal
    INTO v_cur, v_ord
    FROM public.coverage_slots
   WHERE id = p_slot_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'blocked',
      'blocked_reason', 'slot_not_found', 'slot_id', p_slot_id);
  END IF;

  IF v_cur = p_new_status THEN
    RETURN jsonb_build_object('status', 'no_op',
      'reason', 'already_in_status', 'slot_id', p_slot_id, 'slot_status', v_cur);
  END IF;

  IF p_new_status = 'active' AND p_occupant_plantilla_id IS NULL THEN
    RETURN jsonb_build_object('status', 'blocked',
      'blocked_reason', 'occupant_plantilla_required_for_active',
      'slot_id', p_slot_id);
  END IF;

  IF NOT ( (v_cur = 'open'          AND p_new_status = 'pipeline')
        OR (v_cur = 'pipeline'      AND p_new_status = 'open')
        OR (v_cur = 'pipeline'      AND p_new_status = 'hr_processing')
        OR (v_cur = 'hr_processing' AND p_new_status = 'open')
        OR (v_cur = 'hr_processing' AND p_new_status = 'active') ) THEN
    RETURN jsonb_build_object('status', 'blocked',
      'blocked_reason',
        format('edge %s -> %s not owned by R-D (open<->pipeline, '
               'pipeline->hr_processing, hr_processing->open, '
               'hr_processing->active only)', v_cur, p_new_status),
      'slot_id', p_slot_id);
  END IF;

  UPDATE public.coverage_slots
     SET slot_status = p_new_status,
         current_occupant_plantilla_id =
           CASE WHEN p_new_status = 'active' THEN p_occupant_plantilla_id ELSE NULL END,
         updated_at  = now()
   WHERE id = p_slot_id;

  RETURN jsonb_build_object('status', 'ok',
    'slot_id', p_slot_id,
    'from', v_cur,
    'to', p_new_status,
    'slot_ordinal', v_ord,
    'occupant_plantilla_id',
      CASE WHEN p_new_status = 'active' THEN p_occupant_plantilla_id ELSE NULL END);
END;
$$;

COMMENT ON FUNCTION public.fn_set_coverage_slot_status(uuid, text, uuid, text, uuid) IS
  'Phase R-D (OHM2026_0080): central coverage-slot transition helper. Owns '
  'open<->pipeline, pipeline->hr_processing, hr_processing->open, and now exactly '
  'hr_processing->active. Into-active requires a non-NULL occupant Plantilla id and '
  'sets coverage_slots.current_occupant_plantilla_id. active->open and closed edges '
  'remain refused for later seams. Returns jsonb {status: ok|no_op|blocked}.';


-- ============================================================
-- §RD3 — Active Plantilla ownership guards
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_plantilla_one_active_per_coverage_slot
  ON public.plantilla (coverage_slot_id)
  WHERE coverage_slot_id IS NOT NULL
    AND COALESCE(is_deleted, false) = false
    AND status = 'Active';

COMMENT ON INDEX public.uq_plantilla_one_active_per_coverage_slot IS
  'Phase R-D (OHM2026_0080): one Active/non-deleted Plantilla owner per coverage slot. '
  'Historical/deleted Plantilla rows may retain coverage_slot_id for audit.';

ALTER TABLE public.plantilla
  DROP CONSTRAINT IF EXISTS plantilla_slot_coverage_mutex_chk;

ALTER TABLE public.plantilla
  DROP CONSTRAINT IF EXISTS plantilla_roving_coverage_mutex_chk;

ALTER TABLE public.plantilla
  ADD CONSTRAINT plantilla_roving_coverage_mutex_chk
  CHECK (roving_assignment_id IS NULL OR coverage_slot_id IS NULL) NOT VALID;

COMMENT ON CONSTRAINT plantilla_roving_coverage_mutex_chk ON public.plantilla IS
  'Phase R-D (OHM2026_0080): legacy roving Plantilla roving_assignment_id and '
  'coverage-group coverage_slot_id lineages are mutually exclusive per row. '
  'NOT VALID; enforced on new writes.';


-- ============================================================
-- §RD4 — Non-blocking wrapper: exact coverage slot hr_processing→active
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_sync_coverage_slot_to_active(
  p_coverage_slot_id       uuid,
  p_plantilla_id           uuid,
  p_performed_by           uuid DEFAULT NULL,
  p_source_fn              text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF p_coverage_slot_id IS NULL THEN
    RETURN jsonb_build_object('status', 'no_op', 'reason', 'null_coverage_slot');
  END IF;

  IF p_plantilla_id IS NULL THEN
    RETURN jsonb_build_object('status', 'blocked',
      'blocked_reason', 'plantilla_id_required',
      'slot_id', p_coverage_slot_id);
  END IF;

  SELECT public.fn_set_coverage_slot_status(
    p_slot_id               => p_coverage_slot_id,
    p_new_status            => 'active',
    p_performed_by          => p_performed_by,
    p_remarks               => format(
      'Phase R-D / %s / hr_processing->active / coverage_slot=%s / plantilla=%s',
      COALESCE(p_source_fn, 'fn_sync_coverage_slot_to_active'),
      p_coverage_slot_id,
      p_plantilla_id
    ),
    p_occupant_plantilla_id => p_plantilla_id
  ) INTO v_result;

  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_coverage_slot_to_active: % for coverage_slot=% plantilla=% source=% reason=%',
      v_result->>'status',
      p_coverage_slot_id,
      p_plantilla_id,
      COALESCE(p_source_fn, 'unknown'),
      COALESCE(v_result->>'blocked_reason', v_result->>'reason', 'same-state no_op');
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_sync_coverage_slot_to_active: error for coverage_slot=% plantilla=% source=% — % (sqlstate=%)',
    p_coverage_slot_id,
    p_plantilla_id,
    COALESCE(p_source_fn, 'unknown'),
    SQLERRM,
    SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_sync_coverage_slot_to_active(uuid, uuid, uuid, text) IS
  'Phase R-D (OHM2026_0080): non-blocking wrapper for exact coverage-slot '
  'hr_processing->active at move-to-Plantilla. NEVER RAISES into the host workflow.';


-- ============================================================
-- §RD5 — Direct move_to_plantilla patch
-- ============================================================
-- CGCODE rows created by R-C carry assignment_type = 'Stationary' and a
-- non-NULL hr_emploc.coverage_slot_id. They therefore enter the STATIONARY ELSE
-- block below. R-D adds a CGCODE sub-branch at the top of that block and splits
-- the Phase 6.3 tail so coverage slots move hr_processing→active while pure
-- stationary rows continue through fn_sync_slot_to_occupied unchanged.

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

  -- ── STATIONARY PATH / CGCODE COVERAGE SUB-PATH ─────────────────────────────
  ELSE

    IF v_emp.coverage_slot_id IS NOT NULL THEN
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

      -- Close carrier CGCODE vacancy via vacancy_id if available.
      IF v_emp.vacancy_id IS NOT NULL THEN
        UPDATE vacancies
           SET status     = 'Filled',
               updated_at = NOW(),
               updated_by = v_actor
         WHERE id = v_emp.vacancy_id;
      END IF;

      -- ── VCODE fallback: close any remaining Open carrier vacancy ──────────
      UPDATE public.vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE vcode      = v_emp.vcode
         AND status     IN ('Open', 'For Sourcing')
         AND COALESCE(is_archived, false) = false
         AND deleted_at IS NULL;

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
  ELSIF NOT v_is_pool AND v_emp.assignment_type <> 'Roving' THEN
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
  'Moves an HR Emploc record to Plantilla (stationary, legacy roving, CGCODE coverage, or pool path). '
  'Phase R-D (OHM2026_0080/0081C): CGCODE rows with hr_emploc.coverage_slot_id are inserted as '
  'Roving deployment Plantilla rows with coverage_slot_id + coverage_group_id, then the exact '
  'coverage slot moves hr_processing->active via fn_sync_coverage_slot_to_active. Pure stationary '
  'rows continue to use fn_sync_slot_to_occupied unchanged.';


-- ============================================================
-- §RD6 — GRANTs
-- ============================================================

REVOKE ALL ON FUNCTION public.fn_set_coverage_slot_status(uuid, text, uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_set_coverage_slot_status(uuid, text, uuid, text, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_sync_coverage_slot_to_active(uuid, uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_sync_coverage_slot_to_active(uuid, uuid, uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.move_to_plantilla(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.move_to_plantilla(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_to_plantilla(uuid) TO service_role;


-- ============================================================
-- §RD7 — Post-migration validation queries (run manually)
-- ============================================================
--
-- RD1 — Every active coverage slot has exactly one active/non-deleted Plantilla row.
--   SELECT cs.id
--     FROM public.coverage_slots cs
--    WHERE cs.slot_status = 'active'
--      AND (SELECT COUNT(*) FROM public.plantilla p
--            WHERE p.coverage_slot_id = cs.id
--              AND COALESCE(p.is_deleted, false) = false
--              AND p.status = 'Active') <> 1;
--   -- Expected: 0 rows.
--
-- RD2 — No two active/non-deleted Plantilla rows share one coverage_slot_id.
--   SELECT coverage_slot_id, COUNT(*) AS cnt
--     FROM public.plantilla
--    WHERE coverage_slot_id IS NOT NULL
--      AND COALESCE(is_deleted, false) = false
--      AND status = 'Active'
--    GROUP BY coverage_slot_id
--   HAVING COUNT(*) > 1;
--   -- Expected: 0 rows.
--
-- RD3 — No Plantilla row has both legacy roving and coverage slot bindings set.
--   SELECT COUNT(*) AS both_bound
--     FROM public.plantilla
--    WHERE roving_assignment_id IS NOT NULL AND coverage_slot_id IS NOT NULL;
--   -- Expected: 0.
--
-- RD4 — Every active/non-deleted roving Plantilla coverage row has both binding columns.
--   SELECT COUNT(*) AS bad
--     FROM public.plantilla
--    WHERE coverage_slot_id IS NOT NULL
--      AND COALESCE(is_deleted, false) = false
--      AND status = 'Active'
--      AND coverage_group_id IS NULL;
--   -- Expected: 0.
--
-- RD5 — Four-way group agreement for bound roving Plantilla rows.
--   SELECT p.id
--     FROM public.plantilla p
--     JOIN public.coverage_slots cs ON cs.id = p.coverage_slot_id
--     LEFT JOIN public.hr_emploc he ON he.id = p.hr_emploc_id
--     LEFT JOIN public.applicants a ON a.id = he.applicant_id
--    WHERE p.coverage_slot_id IS NOT NULL
--      AND COALESCE(p.is_deleted, false) = false
--      AND p.status = 'Active'
--      AND (cs.coverage_group_id <> p.coverage_group_id
--        OR (he.coverage_group_id IS NOT NULL AND he.coverage_group_id <> p.coverage_group_id)
--        OR (a.coverage_group_id IS NOT NULL AND a.coverage_group_id <> p.coverage_group_id));
--   -- Expected: 0 rows.
--
-- RD6 — No active/non-deleted Plantilla row owns a coverage slot outside active.
--   SELECT p.id, cs.slot_status
--     FROM public.plantilla p
--     JOIN public.coverage_slots cs ON cs.id = p.coverage_slot_id
--    WHERE p.coverage_slot_id IS NOT NULL
--      AND COALESCE(p.is_deleted, false) = false
--      AND p.status = 'Active'
--      AND cs.slot_status <> 'active';
--   -- Expected: 0 rows.
--
-- RD7 — Active coverage-slot occupant link agrees with Plantilla back-reference.
--   SELECT cs.id
--     FROM public.coverage_slots cs
--     LEFT JOIN public.plantilla p
--       ON p.id = cs.current_occupant_plantilla_id
--      AND p.coverage_slot_id = cs.id
--      AND COALESCE(p.is_deleted, false) = false
--      AND p.status = 'Active'
--    WHERE cs.slot_status = 'active'
--      AND (cs.current_occupant_plantilla_id IS NULL OR p.id IS NULL);
--   -- Expected: 0 rows.
--
-- RD8 — FK integrity for Plantilla coverage binding and occupant link.
--   SELECT COUNT(*) AS orphans
--     FROM public.plantilla p
--    WHERE (p.coverage_slot_id IS NOT NULL
--           AND NOT EXISTS (SELECT 1 FROM public.coverage_slots cs WHERE cs.id = p.coverage_slot_id))
--       OR (p.coverage_group_id IS NOT NULL
--           AND NOT EXISTS (SELECT 1 FROM public.coverage_groups cg WHERE cg.id = p.coverage_group_id));
--   -- Expected: 0.
--   SELECT COUNT(*) AS occupant_orphans
--     FROM public.coverage_slots cs
--    WHERE cs.current_occupant_plantilla_id IS NOT NULL
--      AND NOT EXISTS (SELECT 1 FROM public.plantilla p WHERE p.id = cs.current_occupant_plantilla_id);
--   -- Expected: 0.
--
-- RD9 — Move-to-Plantilla binding copy + slot-side/Plantilla-side active counts agree.
--   SELECT p.id
--     FROM public.plantilla p
--     JOIN public.hr_emploc he ON he.id = p.hr_emploc_id
--    WHERE p.coverage_slot_id IS NOT NULL
--      AND (p.coverage_slot_id <> he.coverage_slot_id
--        OR p.coverage_group_id <> he.coverage_group_id);
--   -- Expected: 0 rows.
--   SELECT COALESCE(s.coverage_group_id, p.coverage_group_id) AS coverage_group_id,
--          COALESCE(s.active_slots, 0) AS active_slots,
--          COALESCE(p.active_plantilla, 0) AS active_plantilla
--     FROM (SELECT coverage_group_id, COUNT(*) AS active_slots
--             FROM public.coverage_slots
--            WHERE slot_status = 'active'
--            GROUP BY coverage_group_id) s
--     FULL OUTER JOIN (
--       SELECT coverage_group_id, COUNT(DISTINCT coverage_slot_id) AS active_plantilla
--         FROM public.plantilla
--        WHERE coverage_slot_id IS NOT NULL
--          AND COALESCE(is_deleted, false) = false
--          AND status = 'Active'
--        GROUP BY coverage_group_id
--     ) p ON p.coverage_group_id = s.coverage_group_id
--    WHERE COALESCE(s.active_slots, 0) <> COALESCE(p.active_plantilla, 0);
--   -- Expected: 0 rows.
--
-- RD10 — Reopen-ready: exact slot and ordinal recoverable from active Plantilla.
--   SELECT p.id, p.coverage_slot_id, cs.slot_ordinal
--     FROM public.plantilla p
--     JOIN public.coverage_slots cs ON cs.id = p.coverage_slot_id
--    WHERE p.coverage_slot_id IS NOT NULL
--      AND COALESCE(p.is_deleted, false) = false
--      AND p.status = 'Active'
--      AND cs.slot_status = 'active';
--   -- Expected: every active roving Plantilla has one exact coverage_slot_id + ordinal.
--
-- RD11 — Helper scope: new edge only, active needs occupant.
--   -- On disposable rows in one rolled-back transaction:
--   --   hr_processing→active with occupant returns {status:ok}
--   --   hr_processing→active with NULL occupant returns {status:blocked}
--   --   active→open, active→closed, open→active, pipeline→active return {status:blocked}
--
-- RD12 — Reconciliation + stationary isolation.
--   SELECT cg.id
--     FROM public.coverage_groups cg
--     JOIN (SELECT coverage_group_id, COUNT(*) AS n
--             FROM public.coverage_slots GROUP BY coverage_group_id) c
--       ON c.coverage_group_id = cg.id
--    WHERE cg.archived_at IS NULL
--      AND c.n <> cg.required_headcount;
--   -- Expected: 0 rows.
--   SELECT COUNT(*) AS leaked
--     FROM public.vw_slot_derived_vacancy_shadow v
--    WHERE v.legacy_vcode LIKE 'CG-%';
--   -- Expected: 0. Re-run RB1–RB10, RC1–RC12, and stationary occupy smoke GREEN.
-- ============================================================
