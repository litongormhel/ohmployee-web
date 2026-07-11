-- ============================================================
-- OHM2026_0020 — Phase 6.2: Wire Pipeline → HR Processing Slot Transition
-- Migration: 20260813000002_wire_pipeline_hr_processing_slot_transition.sql
-- Depends on: 20260812000000_fn_set_slot_status.sql   (Phase 6.0 — fn_set_slot_status)
--             20260813000001_wire_open_pipeline_slot_transitions.sql
--               (Phase 6.1 — fn_sync_vacancy_slot_open_pipeline)
--             20260522040000_add_hired_date_to_confirm_applicant_onboard.sql
--               (confirm_applicant_onboard — latest live version with p_hired_date)
-- ============================================================
-- Phase 6.2 of slot_lifecycle_automation_plan.md (OHM2026_0017).
--
-- SCOPE: Wire the pipeline → hr_processing slot transition into
-- confirm_applicant_onboard, which is the only existing RPC that
-- creates an HR Emploc record and locks the vacancy. No other workflow,
-- vacancy/applicant behavior, HR Emploc behavior, UI, or migration
-- is changed in any way.
--
-- Hook point:
--   confirm_applicant_onboard — after the shared audit-log INSERT
--   and before the final RETURN, on the non-fast-track, non-roving
--   stationary path only. Both fast-track paths (existing Plantilla
--   employee and roving duplicate guard) return early and are NOT
--   affected by this hook.
--
-- Slot lookup: plantilla_slots.legacy_vcode = v_vac.vcode (1:1 bridge,
--   per OHM2026_0017 Q6). Relies on the partial-unique index on
--   legacy_vcode established in 20260807000000_plantilla_slots_legacy_vcode_link.sql.
--
-- Reason code: REPLACEMENT — task-specified for this transition,
--   recording that a pipeline applicant has advanced to HR Emploc
--   processing (the slot is being filled again after a vacancy).
--   Note: the design plan Q2/Q3 marks this as *(none)*, but OHM2026_0020
--   explicitly requires REPLACEMENT here for Phase 6.2 traceability.
--
-- Non-blocking contract (hard requirement — OHM2026_0017 Q1):
--   A slot sync error must NEVER roll back or alter the host RPC's
--   transaction. fn_sync_slot_to_hr_processing (§1) catches ALL
--   exceptions internally and emits RAISE NOTICE only.
--
-- Roving carve-out:
--   Roving slots (is_roving = true) are skipped unconditionally — no
--   reliable 1:1 VCODE→slot mapping until the deferred coverage model
--   lands (OHM2026_0017 Q6). The guard is applied at two levels:
--   (a) the host RPC guard (IF NOT v_is_roving) before calling the helper;
--   (b) the helper itself also filters is_roving = false on the slot lookup.
--
-- P1–P8 reconciliation impact:
--   After Phase 6.2, slots moved to hr_processing no longer appear in the
--   shadow Vacancy view (which only projects open and pipeline states).
--   The legacy Vacancy view continues to show those VCODEs as Open (the
--   'Confirmed Onboard' applicant status is not counted as active, so
--   active_applicant_count = 0 → legacy derived_status = Open). This
--   expected divergence (shadow shows fewer than legacy) will persist until
--   Phase 7 (flag-gated UI cutover). Re-run the P1–P8 suite after
--   Phase 6.2 to baseline the new expected counts.
--
-- Sections:
--   §1  fn_sync_slot_to_hr_processing  (internal non-blocking helper)
--   §2  Patch confirm_applicant_onboard (slot sync hook added)
--   §3  GRANT
-- ============================================================


-- ============================================================
-- §1  fn_sync_slot_to_hr_processing
-- ============================================================
-- Non-blocking internal helper that transitions a vacancy slot from
-- pipeline to hr_processing after confirm_applicant_onboard succeeds.
--
-- Called AFTER the host RPC has written the HR Emploc row and the
-- audit log, so the transition represents confirmed state.
--
-- Arguments
-- ---------
--   p_vcode        — Vacancy VCODE (vacancies.vcode / applicants.vacancy_vcode).
--   p_applicant_id — Applicant UUID written to slot_history.remarks (nullable).
--   p_performed_by — Acting user UUID for slot_history.performed_by (nullable).
--   p_source_fn    — Calling function name; written to slot_history.remarks.
--
-- Returns: JSONB from fn_set_slot_status (ok / no_op / blocked), or NULL
--          when skipped (roving, no slot, null vcode, or any error).
-- NEVER RAISES.

CREATE OR REPLACE FUNCTION public.fn_sync_slot_to_hr_processing(
  p_vcode        text,
  p_applicant_id uuid DEFAULT NULL,
  p_performed_by uuid DEFAULT NULL,
  p_source_fn    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
/*
  Phase 6.2 — non-blocking pipeline→hr_processing slot sync (OHM2026_0020).

  Locates the slot by legacy_vcode (1:1 bridge, non-roving only).
  Delegates to fn_set_slot_status with:
    p_new_status  = 'hr_processing'
    p_reason_code = 'REPLACEMENT'   (OHM2026_0020 task spec)

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
      'fn_sync_slot_to_hr_processing: skipped — p_vcode is null/empty (source=%)',
      COALESCE(p_source_fn, 'unknown');
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
  -- fn_set_slot_status handles: same-state no_op, matrix validation,
  -- slot row update (slot_status + updated_at/by), and slot_history append.
  -- Reason code REPLACEMENT is task-specified for Phase 6.2.
  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => 'hr_processing',
    p_reason_code           => 'REPLACEMENT',
    p_performed_by          => p_performed_by,
    p_remarks               => format(
                                 'Phase 6.2 / %s / VCODE=%s / applicant_id=%s',
                                 COALESCE(p_source_fn, 'unknown'),
                                 p_vcode,
                                 COALESCE(p_applicant_id::text, 'null')
                               ),
    p_occupant_plantilla_id => NULL
  ) INTO v_result;

  -- Log blocked/no_op outcomes for observability; never raise.
  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_slot_to_hr_processing: % for slot_id=% VCODE=% source=% — %',
      v_result->>'status',
      v_slot_id,
      p_vcode,
      COALESCE(p_source_fn, 'unknown'),
      COALESCE(v_result->>'blocked_reason', 'same-state no_op');
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  -- Non-blocking contract: log and skip. Host RPC transaction continues.
  RAISE NOTICE
    'fn_sync_slot_to_hr_processing: error for VCODE=% source=% — % (sqlstate=%)',
    p_vcode, COALESCE(p_source_fn, 'unknown'), SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_sync_slot_to_hr_processing(text, uuid, uuid, text) IS
  'Phase 6.2 — non-blocking pipeline→hr_processing slot sync helper (OHM2026_0020). '
  'Called after confirm_applicant_onboard succeeds on the stationary non-fast-track path. '
  'Locates slot by legacy_vcode (non-roving only), calls fn_set_slot_status with '
  'p_new_status=hr_processing and p_reason_code=REPLACEMENT. '
  'NEVER raises. Blocked/no_op results are RAISE NOTICEd and returned. '
  'Callers: confirm_applicant_onboard (stationary non-fast-track path only).';


-- ============================================================
-- §2  Patch confirm_applicant_onboard (Phase 6.2 slot sync hook)
-- ============================================================
-- Source: 20260522040000_add_hired_date_to_confirm_applicant_onboard.sql
--   (latest version — adds p_hired_date parameter).
-- Change: ONE addition — fn_sync_slot_to_hr_processing call inserted
--         after the shared audit-log INSERT and before the final RETURN.
--         The hook is guarded with IF NOT v_is_roving so roving paths
--         are never touched.
-- All existing behavior — parameters, RBAC, idempotency guard,
-- fast-track branches (both), roving/stationary HR Emploc creation,
-- store-link management, audit log, return shape, SECURITY DEFINER,
-- GRANT — is preserved IDENTICALLY.
-- No parameter or return type changes.

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
  p_hired_date               date    DEFAULT NULL::date
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
  -- fast-track vars
  v_existing_plt      public.plantilla%ROWTYPE;
  v_roving_id         uuid;
  v_new_roving        boolean := false;
  v_plt_store_link_id uuid;
  v_existing_employee_no text;
  v_roving_hr_found   boolean := false;
BEGIN
  -- ── RBAC ────────────────────────────────────────────────────────────────
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Data Team, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch and lock applicant ─────────────────────────────────────────────
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
      'cannot confirm onboarding: applicant is in terminal status %', v_app.status
      USING ERRCODE = '22023';
  END IF;

  -- ── Resolve roving flag ───────────────────────────────────────────────────
  v_is_roving := COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL;

  -- ── Idempotent guard ─────────────────────────────────────────────────────
  IF v_app.status = 'Confirmed Onboard' THEN
    IF v_is_roving THEN
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
         AND assignment_type = 'Roving'
         AND deleted_at IS NULL
       ORDER BY created_at ASC LIMIT 1;
    ELSE
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE deleted_at IS NULL
         AND (
           applicant_id = v_app.id
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

  -- ── Fetch and lock vacancy ────────────────────────────────────────────────
  SELECT * INTO v_vac
    FROM public.vacancies
   WHERE vcode = v_app.vacancy_vcode
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'active vacancy not found for vcode %', v_app.vacancy_vcode
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_vac.has_pending_closure, false) = true THEN
    RAISE EXCEPTION
      'onboarding blocked: vacancy % has a pending closure request. Withdraw the closure request first.',
      v_vac.vcode
      USING ERRCODE = '55000';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_vac.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: vacancy is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  IF p_contact_number IS NOT NULL AND btrim(p_contact_number) <> '' THEN
    PERFORM public.fn_validate_ph_contact_number(p_contact_number);
  END IF;

  -- ── Resolve full name ─────────────────────────────────────────────────────
  v_full_name := COALESCE(
    NULLIF(btrim(p_full_name), ''),
    NULLIF(btrim(concat_ws(' ',
      NULLIF(p_first_name, ''),
      NULLIF(p_middle_name, ''),
      NULLIF(p_last_name, '')
    )), ''),
    v_app.full_name
  );

  v_hired_by_id := COALESCE(p_hired_by_user_id, v_profile_id);

  -- ── Update applicant ─────────────────────────────────────────────────────
  -- p_hired_date (caller-supplied) takes precedence over any existing
  -- hired_date; falls back to CURRENT_DATE only when both are absent.
  UPDATE public.applicants
  SET
    last_name                = COALESCE(NULLIF(p_last_name, ''),    last_name),
    first_name               = COALESCE(NULLIF(p_first_name, ''),   first_name),
    middle_name              = p_middle_name,
    full_name                = v_full_name,
    full_name_snapshot       = v_full_name,
    contact_number           = COALESCE(NULLIF(p_contact_number, ''), contact_number),
    remarks                  = p_remarks,
    roving_assignment_id     = COALESCE(p_roving_assignment_id, roving_assignment_id),
    status                   = 'Confirmed Onboard',
    hired_date               = COALESCE(p_hired_date, hired_date, CURRENT_DATE),
    hired_at                 = COALESCE(hired_at, NOW()),
    hired_by                 = v_actor_name,
    hired_by_team            = v_role,
    hired_by_user_id         = v_hired_by_id,
    endorsed_by_deployer_id  = p_endorsed_by_deployer_id,
    endorsed_by_name         = p_endorsed_by_name,
    deployed_by_user_id      = v_profile_id,
    is_archived              = false,
    updated_at               = NOW(),
    updated_by               = v_profile_id
  WHERE id = p_applicant_id
  RETURNING * INTO v_app;

  -- ── Existing employee fast-track ──────────────────────────────────────────
  -- Employee numbers already in active Plantilla do not go back through HR
  -- Emploc. For roving/multi-store approvals, reuse the existing Plantilla
  -- employee and add/activate only the missing store assignment.
  SELECT * INTO v_existing_plt
    FROM public.plantilla
   WHERE account = v_vac.account
     AND status = 'Active'
     AND is_deleted = false
     AND employee_no IS NOT NULL
     AND (
       (
         COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL
         AND roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
       )
       OR LOWER(TRIM(employee_name)) = LOWER(TRIM(v_full_name))
     )
   ORDER BY
     CASE
       WHEN roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) THEN 0
       ELSE 1
     END,
     created_at DESC
   LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    v_roving_id := COALESCE(
      v_existing_plt.roving_assignment_id,
      p_roving_assignment_id,
      v_app.roving_assignment_id
    );

    IF v_roving_id IS NULL THEN
      INSERT INTO public.roving_assignments (
        master_applicant_id, account, account_id,
        primary_vcode, label, created_by, updated_by
      ) VALUES (
        v_app.id, v_vac.account, v_vac.account_id,
        COALESCE(v_existing_plt.vcode, v_vac.vcode),
        v_full_name,
        v_profile_id, v_profile_id
      )
      RETURNING id INTO v_roving_id;

      v_new_roving := true;
    END IF;

    UPDATE public.applicants
    SET
      roving_assignment_id = v_roving_id,
      updated_at = NOW(),
      updated_by = v_profile_id
    WHERE id = v_app.id
    RETURNING * INTO v_app;

    UPDATE public.plantilla
    SET
      deployment_type      = 'Roving',
      roving_assignment_id = v_roving_id,
      updated_at           = NOW(),
      updated_by           = v_profile_id
    WHERE id = v_existing_plt.id;

    IF v_existing_plt.vcode IS NOT NULL THEN
      SELECT id INTO v_plt_store_link_id
        FROM public.plantilla_store_links
       WHERE plantilla_id = v_existing_plt.id
         AND roving_assignment_id = v_roving_id
         AND (vacancy_id = v_existing_plt.vacancy_id OR vcode = v_existing_plt.vcode)
         AND deleted_at IS NULL
       LIMIT 1
      FOR UPDATE;

      IF v_plt_store_link_id IS NULL THEN
        INSERT INTO public.plantilla_store_links (
          plantilla_id, roving_assignment_id,
          vacancy_id, vcode, store_name, account,
          status, linked_at, linked_by, created_by, updated_by
        ) VALUES (
          v_existing_plt.id, v_roving_id,
          v_existing_plt.vacancy_id, v_existing_plt.vcode,
          v_existing_plt.store_name, v_existing_plt.account,
          'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
        )
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;

    v_plt_store_link_id := NULL;

    SELECT id INTO v_plt_store_link_id
      FROM public.plantilla_store_links
     WHERE plantilla_id = v_existing_plt.id
       AND roving_assignment_id = v_roving_id
       AND (
         vacancy_id = v_vac.id
         OR vcode = v_vac.vcode
         OR (
           account = v_vac.account
           AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, '')))
         )
       )
       AND deleted_at IS NULL
     LIMIT 1
    FOR UPDATE;

    IF v_plt_store_link_id IS NULL THEN
      INSERT INTO public.plantilla_store_links (
        plantilla_id, roving_assignment_id,
        vacancy_id, vcode, store_name, account,
        status, linked_at, linked_by, created_by, updated_by
      ) VALUES (
        v_existing_plt.id, v_roving_id,
        v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
        'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
      )
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_plt_store_link_id;

      IF v_plt_store_link_id IS NULL THEN
        SELECT id INTO v_plt_store_link_id
         FROM public.plantilla_store_links
         WHERE plantilla_id = v_existing_plt.id
           AND roving_assignment_id = v_roving_id
           AND (
             vacancy_id = v_vac.id
             OR vcode = v_vac.vcode
             OR (
               account = v_vac.account
               AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, '')))
             )
           )
           AND deleted_at IS NULL
         LIMIT 1;
      END IF;
    ELSE
      UPDATE public.plantilla_store_links
      SET
        status      = 'Active',
        unlinked_at = NULL,
        unlinked_by = NULL,
        updated_at  = NOW(),
        updated_by  = v_profile_id
      WHERE id = v_plt_store_link_id;
    END IF;

    UPDATE public.vacancies
    SET
      status     = 'Filled',
      updated_at = NOW(),
      updated_by = v_profile_id
    WHERE id = v_vac.id;

    INSERT INTO public.employee_activity_log (
      emploc_no, vcode, activity_type, description, performed_by, metadata
    ) VALUES (
      COALESCE(v_existing_plt.emploc_no, v_existing_plt.employee_no, v_app.full_name),
      v_vac.vcode,
      'confirmed_onboard_fast_track',
      'Existing Plantilla employee fast-tracked to new store, bypassing HR Emploc queue for ' || v_vac.vcode,
      v_actor_name,
      jsonb_build_object(
        'applicant_id',              v_app.id,
        'hr_emploc_id',              NULL,
        'plantilla_id',              v_existing_plt.id,
        'plantilla_store_link_id',   v_plt_store_link_id,
        'vacancy_id',                v_vac.id,
        'employee_no',               v_existing_plt.employee_no,
        'roving_assignment_id',      v_roving_id,
        'new_roving_created',        v_new_roving,
        'skipped_hr_emploc',         true,
        'role',                      v_role,
        'hired_by_user_id',          v_hired_by_id,
        'hired_date',                v_app.hired_date,
        'movement_at',               NOW()
      )
    );

    -- Fast-track: existing Plantilla employee bypasses HR Emploc entirely.
    -- No slot sync here — this path skips the hr_processing state and goes
    -- directly to occupied (handled by Phase 6.3 in move_to_plantilla).
    RETURN jsonb_build_object(
      'ok',                       true,
      'applicant_id',             v_app.id,
      'applicant_status',         v_app.status,
      'hr_emploc_id',             NULL,
      'plantilla_id',             v_existing_plt.id,
      'plantilla_store_link_id',  v_plt_store_link_id,
      'vcode',                    v_vac.vcode,
      'hired_by_user_id',         v_hired_by_id,
      'hired_date',               v_app.hired_date,
      'is_roving',                true,
      'fast_tracked',             true,
      'skipped_hr_emploc',        true,
      'new_roving_created',       v_new_roving
    );
  END IF;

  -- ── Find or create HR Emploc ──────────────────────────────────────────────
  IF v_is_roving THEN
    -- ROVING: look for existing master by roving_assignment_id
    SELECT * INTO v_hr
      FROM public.hr_emploc
     WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
       AND assignment_type = 'Roving'
       AND deleted_at IS NULL
     ORDER BY created_at ASC LIMIT 1
    FOR UPDATE;

    v_roving_hr_found := FOUND;

    IF v_roving_hr_found THEN
      v_existing_employee_no := COALESCE(
        NULLIF(BTRIM(v_hr.employee_no), ''),
        NULLIF(BTRIM(v_hr.emploc_no), '')
      );

      IF v_hr.status = 'Moved to Plantilla' OR v_existing_employee_no IS NOT NULL THEN
        SELECT * INTO v_existing_plt
          FROM public.plantilla
         WHERE is_deleted = false
           AND status IN ('Active', 'For Deactivation', 'On Leave')
           AND (
             roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
             OR hr_emploc_id = v_hr.id
             OR (
               v_existing_employee_no IS NOT NULL
               AND employee_no = v_existing_employee_no
               AND account = v_vac.account
             )
           )
         ORDER BY
           CASE
             WHEN roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) THEN 0
             WHEN hr_emploc_id = v_hr.id THEN 1
             ELSE 2
           END,
           created_at DESC
         LIMIT 1
        FOR UPDATE;

        IF FOUND THEN
          v_roving_id := COALESCE(
            v_existing_plt.roving_assignment_id,
            v_hr.roving_assignment_id,
            p_roving_assignment_id,
            v_app.roving_assignment_id
          );

          UPDATE public.applicants
          SET
            roving_assignment_id = v_roving_id,
            updated_at = NOW(),
            updated_by = v_profile_id
          WHERE id = v_app.id
          RETURNING * INTO v_app;

          UPDATE public.plantilla
          SET
            deployment_type      = 'Roving',
            roving_assignment_id = v_roving_id,
            updated_at           = NOW(),
            updated_by           = v_profile_id
          WHERE id = v_existing_plt.id;

          SELECT id INTO v_plt_store_link_id
            FROM public.plantilla_store_links
           WHERE plantilla_id = v_existing_plt.id
             AND roving_assignment_id = v_roving_id
             AND (
               vacancy_id = v_vac.id
               OR vcode = v_vac.vcode
               OR (
                 account = v_vac.account
                 AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, '')))
               )
             )
             AND deleted_at IS NULL
           LIMIT 1
          FOR UPDATE;

          IF v_plt_store_link_id IS NULL THEN
            INSERT INTO public.plantilla_store_links (
              plantilla_id, roving_assignment_id,
              vacancy_id, vcode, store_name, account,
              status, linked_at, linked_by, created_by, updated_by
            ) VALUES (
              v_existing_plt.id, v_roving_id,
              v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
              'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
            )
            ON CONFLICT DO NOTHING
            RETURNING id INTO v_plt_store_link_id;

            IF v_plt_store_link_id IS NULL THEN
              SELECT id INTO v_plt_store_link_id
                FROM public.plantilla_store_links
               WHERE plantilla_id = v_existing_plt.id
                 AND roving_assignment_id = v_roving_id
                 AND (
                   vacancy_id = v_vac.id
                   OR vcode = v_vac.vcode
                   OR (
                     account = v_vac.account
                     AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, '')))
                   )
                 )
                 AND deleted_at IS NULL
               LIMIT 1;
            END IF;
          ELSE
            UPDATE public.plantilla_store_links
            SET
              status      = 'Active',
              unlinked_at = NULL,
              unlinked_by = NULL,
              updated_at  = NOW(),
              updated_by  = v_profile_id
            WHERE id = v_plt_store_link_id;
          END IF;

          UPDATE public.vacancies
          SET
            status     = 'Filled',
            updated_at = NOW(),
            updated_by = v_profile_id
          WHERE id = v_vac.id;

          INSERT INTO public.employee_activity_log (
            emploc_no, vcode, activity_type, description, performed_by, metadata
          ) VALUES (
            COALESCE(v_existing_plt.emploc_no, v_existing_plt.employee_no, v_existing_employee_no, v_app.full_name),
            v_vac.vcode,
            'confirmed_onboard_fast_track',
            'Existing roving employee fast-tracked to new store, bypassing duplicate HR Emploc creation for ' || v_vac.vcode,
            v_actor_name,
            jsonb_build_object(
              'applicant_id',              v_app.id,
              'hr_emploc_id',              v_hr.id,
              'plantilla_id',              v_existing_plt.id,
              'plantilla_store_link_id',   v_plt_store_link_id,
              'vacancy_id',                v_vac.id,
              'employee_no',               COALESCE(v_existing_plt.employee_no, v_existing_employee_no),
              'roving_assignment_id',      v_roving_id,
              'skipped_hr_emploc_insert',  true,
              'role',                      v_role,
              'hired_by_user_id',          v_hired_by_id,
              'hired_date',                v_app.hired_date,
              'movement_at',               NOW()
            )
          );

          -- Roving fast-track duplicate guard: no slot sync (roving carve-out).
          RETURN jsonb_build_object(
            'ok',                       true,
            'applicant_id',             v_app.id,
            'applicant_status',         v_app.status,
            'hr_emploc_id',             v_hr.id,
            'plantilla_id',             v_existing_plt.id,
            'plantilla_store_link_id',  v_plt_store_link_id,
            'vcode',                    v_vac.vcode,
            'hired_by_user_id',         v_hired_by_id,
            'hired_date',               v_app.hired_date,
            'is_roving',                true,
            'fast_tracked',             true,
            'skipped_hr_emploc',        true,
            'duplicate_roving_guard',   true
          );
        END IF;
      END IF;
    END IF;

    IF NOT v_roving_hr_found THEN
      -- First store: create roving master
      -- hired_date sourced from v_app.hired_date which already reflects
      -- COALESCE(p_hired_date, hired_date, CURRENT_DATE) from the UPDATE above.
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_code_snapshot,
        account, account_id, chain_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Roving'::public.hr_emploc_assignment_type,
        COALESCE(p_roving_assignment_id, v_app.roving_assignment_id),
        '[]'::jsonb
      )
      ON CONFLICT DO NOTHING
      RETURNING * INTO v_hr;

      IF v_hr.id IS NULL THEN
        SELECT * INTO v_hr
          FROM public.hr_emploc
         WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
           AND assignment_type = 'Roving'
           AND deleted_at IS NULL
         ORDER BY created_at ASC LIMIT 1
        FOR UPDATE;
      END IF;
    END IF;

    -- Insert store link (idempotent)
    INSERT INTO public.hr_emploc_store_links (
      hr_emploc_id, roving_assignment_id, vacancy_id, vcode,
      store_name, account, status, confirmed_at, confirmed_by,
      created_by, updated_by
    ) VALUES (
      v_hr.id,
      COALESCE(p_roving_assignment_id, v_app.roving_assignment_id),
      v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
      'Confirmed', NOW(), v_profile_id, v_profile_id, v_profile_id
    )
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_store_link_id;

    -- ── Late store auto-link ─────────────────────────────────────────────
    -- If master already in Plantilla, auto-link this store
    IF v_hr.status = 'Moved to Plantilla' AND v_store_link_id IS NOT NULL THEN
      SELECT public.link_late_store_to_plantilla(v_store_link_id) INTO v_late_result;
    END IF;

  ELSE
    -- STATIONARY: original logic unchanged
    SELECT * INTO v_hr
      FROM public.hr_emploc
     WHERE deleted_at IS NULL
       AND (
         applicant_id = v_app.id
         OR (applicant_name = v_app.full_name AND vcode = v_app.vacancy_vcode)
       )
     ORDER BY created_at DESC LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
      -- hired_date sourced from v_app.hired_date which already reflects
      -- COALESCE(p_hired_date, hired_date, CURRENT_DATE) from the UPDATE above.
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_id, vacancy_code_snapshot,
        account, account_id, chain_id, store_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        store_name, hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.id, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.store_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.store_name, v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Stationary'::public.hr_emploc_assignment_type,
        NULL, '[]'::jsonb
      )
      RETURNING * INTO v_hr;
    END IF;
  END IF;

  -- ── Audit log ────────────────────────────────────────────────────────────
  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    COALESCE(v_hr.emploc_no, v_app.full_name),
    v_vac.vcode,
    'confirmed_onboard',
    'Applicant confirmed onboard and moved to HR Emploc for ' || v_vac.vcode,
    v_actor_name,
    jsonb_build_object(
      'applicant_id',            v_app.id,
      'hr_emploc_id',            v_hr.id,
      'vacancy_id',              v_vac.id,
      'role',                    v_role,
      'hired_by_user_id',        v_hired_by_id,
      'endorsed_by_deployer_id', p_endorsed_by_deployer_id,
      'endorsed_by_name',        p_endorsed_by_name,
      'is_roving',               v_is_roving,
      'hired_date',              v_app.hired_date,
      'late_store_linked',       v_late_result IS NOT NULL,
      'movement_at',             NOW()
    )
  );

  -- ── Phase 6.2: non-blocking slot pipeline→hr_processing sync ─────────────
  -- Wires the Vacancy→HR Emploc transition into the slot lifecycle model.
  -- Only fires for stationary (non-roving) applicants; roving slots have no
  -- reliable 1:1 VCODE→slot mapping and are deferred (OHM2026_0017 Q6).
  -- fn_sync_slot_to_hr_processing NEVER raises; a slot error will not roll
  -- back this function's HR Emploc creation, audit log, or applicant writes.
  IF NOT v_is_roving THEN
    PERFORM public.fn_sync_slot_to_hr_processing(
      p_vcode        => v_vac.vcode,
      p_applicant_id => v_app.id,
      p_performed_by => v_profile_id,
      p_source_fn    => 'confirm_applicant_onboard'
    );
  END IF;

  RETURN jsonb_build_object(
    'ok',               true,
    'applicant_id',     v_app.id,
    'applicant_status', v_app.status,
    'hr_emploc_id',     v_hr.id,
    'vcode',            v_vac.vcode,
    'hired_by_user_id', v_hired_by_id,
    'hired_date',       v_app.hired_date,
    'is_roving',        v_is_roving,
    'late_store_linked', v_late_result
  );
END;
$function$;

COMMENT ON FUNCTION public.confirm_applicant_onboard(uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date) IS
  'Confirms an applicant for onboarding and creates the HR Emploc record. '
  'Phase 6.2 (OHM2026_0020): also syncs the matching plantilla slot pipeline→hr_processing '
  'after the audit log write, on the stationary non-fast-track path only, '
  'via fn_sync_slot_to_hr_processing (non-blocking). '
  'Roving slots are excluded (carve-out: no reliable 1:1 VCODE→slot until coverage model).';


-- ============================================================
-- §3  GRANT
-- ============================================================
-- fn_sync_slot_to_hr_processing is an internal helper called
-- only from SECURITY DEFINER RPCs; restrict to authenticated.

REVOKE ALL ON FUNCTION public.fn_sync_slot_to_hr_processing(text, uuid, uuid, text)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_sync_slot_to_hr_processing(text, uuid, uuid, text)
  TO authenticated;

-- Preserve existing GRANT on confirm_applicant_onboard (unchanged from 20260522040000).
GRANT EXECUTE ON FUNCTION public.confirm_applicant_onboard(
  uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date
) TO authenticated;


-- ============================================================
-- Validation Queries (run manually after applying)
-- ============================================================
--
-- V1 — Helper function exists with correct signature
--   SELECT routine_name, routine_type, security_type
--   FROM information_schema.routines
--   WHERE routine_schema = 'public'
--     AND routine_name = 'fn_sync_slot_to_hr_processing';
--   -- Expected: 1 row, FUNCTION, DEFINER
--
-- V2 — confirm_applicant_onboard body includes Phase 6.2 hook
--   SELECT prosrc LIKE '%fn_sync_slot_to_hr_processing%'
--   FROM pg_proc
--   WHERE proname = 'confirm_applicant_onboard'
--     AND pronamespace = 'public'::regnamespace;
--   -- Expected: true
--
-- V3 — Slot moves pipeline → hr_processing on stationary onboard
--   (After confirming a stationary applicant for a VCODE that has a slot
--    currently in pipeline status)
--   SELECT slot_status FROM public.plantilla_slots
--   WHERE legacy_vcode = '<test_vcode>';
--   -- Expected: 'hr_processing'
--
--   SELECT action_type, old_value, new_value, reason_code, remarks
--   FROM public.slot_history
--   WHERE slot_id = (SELECT id FROM public.plantilla_slots WHERE legacy_vcode = '<test_vcode>')
--   ORDER BY created_at DESC LIMIT 5;
--   -- Expected: one row with action_type='hr_processing', old_value='pipeline',
--   --           new_value='hr_processing', reason_code='REPLACEMENT',
--   --           remarks includes 'Phase 6.2 / confirm_applicant_onboard / VCODE=...'
--
-- V4 — confirm_applicant_onboard still returns expected shape
--   (Call with a valid stationary applicant)
--   -- Expected JSONB: {ok: true, applicant_id, applicant_status: 'Confirmed Onboard',
--   --                  hr_emploc_id, vcode, hired_by_user_id, hired_date, is_roving: false,
--   --                  late_store_linked}
--   -- Shape is identical to pre-Phase-6.2 — no new keys added.
--
-- V5 — Roving paths NOT touched by Phase 6.2 sync
--   SELECT slot_status FROM public.plantilla_slots
--   WHERE is_roving = true;
--   -- Status must match pre-migration snapshot (Phase 6.2 never writes roving slots)
--
-- V6 — No Vacancy UI read-source behavior changed
--   SELECT count(*) FROM public.vacancies
--   WHERE status NOT IN ('Filled', 'Cancelled');
--   -- Compare to pre-migration count; must be identical.
--   -- (confirm_applicant_onboard does NOT set vacancy.status — that stays in move_to_plantilla)
--
-- V7 — slot_history written only on successful stationary transition
--   SELECT count(*) FROM public.slot_history
--   WHERE remarks LIKE 'Phase 6.2%'
--     AND action_type != 'hr_processing';
--   -- Expected: 0 (only hr_processing action_type written by Phase 6.2)
--
-- V8 — P1–P8 reconciliation baseline after Phase 6.2
--   (Re-run the parity suite from OHM2026_0016 / 20260811000000_fix_backfill_parity_d1_d2.sql)
--   NOTE: hr_processing slots are excluded from the shadow Vacancy view (open+pipeline only).
--   Any slot now in hr_processing will appear in legacy as Open (active_applicant_count=0
--   after Confirmed Onboard status) but NOT in the shadow view. This expected divergence
--   is baseline for Phase 6.2 and resolves in Phase 7 (UI cutover).
--
-- V9 — REPLACEMENT reason code is valid in slot_reason_codes
--   SELECT code, label FROM public.slot_reason_codes WHERE code = 'REPLACEMENT';
--   -- Expected: 1 row (defined in 20260804000000_plantilla_slot_foundation_v1.sql)
-- ============================================================
