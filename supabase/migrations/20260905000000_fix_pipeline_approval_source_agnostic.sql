-- ============================================================
-- OHM2026_0068 — Fix Pipeline Approval: Source-Agnostic + Controlled Error Guard
-- Migration: 20260905000000_fix_pipeline_approval_source_agnostic.sql
-- Depends on: 20260824000000_coverage_group_phase_rc_hr_emploc_binding.sql
-- ============================================================
-- Root Cause
--   confirm_applicant_onboard fetches the vacancy with:
--     WHERE vcode = v_app.vacancy_vcode
--       AND COALESCE(is_archived, false) = false
--       AND deleted_at IS NULL
--   When the vacancy is archived (is_archived=true) or soft-deleted
--   (deleted_at IS NOT NULL — as happens after approve_vacancy_import_rollback),
--   the lookup returns NOT FOUND and the function raises:
--     RAISE EXCEPTION 'active vacancy not found for vcode %' USING ERRCODE='P0002'
--   PostgREST surfaces ERRCODE P0002 as a raw JSON 404, which the Flutter client
--   displays as a raw red snackbar: "Failed to confirm onboarding: ...json...".
--
-- Failure Scenarios Confirmed
--   1. Vacancy Import → rollback (deleted_at IS NOT NULL) while applicant cache
--      is stale on the client — tapping Approve fires RPC on soft-deleted vacancy.
--   2. Vacancy (any source: hc_request, manual, migration) archived by SA/HA while
--      an active Pipeline applicant exists — same lookup failure.
--   3. Vacancy row deleted/missing entirely (data issue).
--
-- Source-Agnostic Guarantee
--   The vacancy lookup already does NOT branch on vacancies.source.
--   Vacancies created via hc_request, migration (import), manual, or restored-import
--   all satisfy the same WHERE predicate when active. This migration makes that
--   explicit in a comment and adds a diagnostic guard that covers ALL sources
--   equally — no special-casing for HC Request, Import, or any other origin.
--
-- Fix
--   The ONLY change vs 20260824000000 confirm_applicant_onboard:
--   §1  Add v_diag_is_archived + v_diag_deleted_at to DECLARE block.
--   §2  Replace the raw P0002 RAISE with a two-step diagnostic guard that:
--       a. Queries vacancies for the vcode without the active-state filters.
--       b. Raises ERRCODE='22023' (invalid_parameter_value) — a HTTP 400 via
--          PostgREST instead of 404 — with a prefixed, machine-parseable code:
--           VACANCY_ARCHIVED  — is_archived=true (restore before approving)
--           VACANCY_REMOVED   — deleted_at IS NOT NULL (rollback / import removal)
--           VACANCY_NOT_FOUND — no row at all (data issue)
--       The Flutter catch handler reads the prefix and surfaces a clean message.
--
-- HC Capacity (multi-HC)
--   confirm_applicant_onboard has never blocked on HC capacity — it assumes the
--   Flutter-side _assertVacancySlotAvailable guard (fixed OHM2026_0066) has already
--   run. This is unchanged. Both hc_request and import vacancies share the same
--   capacity rule (pipelineCount + hrProcessingCount + occupiedCount >= requiredHc).
--
-- All other confirm_applicant_onboard behavior is IDENTICAL to the RC phase
-- (20260824000000). No other function, table, view, or trigger is touched.
--
-- Replay safety: CREATE OR REPLACE — idempotent.
-- ============================================================

-- ============================================================
-- §1+2  Replace confirm_applicant_onboard
--        ONLY changes vs 20260824000000:
--        DECLARE: +v_diag_is_archived, +v_diag_deleted_at
--        NOT FOUND block: raw P0002 → diagnostic guard (ERRCODE 22023)
-- ============================================================

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
  -- §1 OHM2026_0068: diagnostic vars for controlled NOT FOUND error (vacancy lookup)
  v_diag_is_archived  boolean;
  v_diag_deleted_at   timestamptz;
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
  -- §2 OHM2026_0068: Source-agnostic — hc_request, migration/import, manual, and
  -- restored-import vacancies are treated identically. The vacancy.source column is
  -- NEVER consulted for approval eligibility; only is_archived and deleted_at matter.
  SELECT * INTO v_vac
    FROM public.vacancies
   WHERE vcode = v_app.vacancy_vcode
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    -- Controlled diagnostic guard: distinguish the exact reason so the Flutter
    -- client receives a machine-parseable prefix and a human-readable message
    -- instead of a raw PostgREST P0002 (no_data_found) exception.
    -- ERRCODE 22023 (invalid_parameter_value) → HTTP 400 via PostgREST, which
    -- the Flutter catch handler decodes into a clean snackbar message.
    SELECT COALESCE(is_archived, false), deleted_at
      INTO v_diag_is_archived, v_diag_deleted_at
      FROM public.vacancies
     WHERE vcode = v_app.vacancy_vcode
     LIMIT 1;

    IF FOUND AND v_diag_is_archived THEN
      RAISE EXCEPTION 'VACANCY_ARCHIVED: Vacancy % has been archived. Restore the vacancy before approving.',
        v_app.vacancy_vcode
        USING ERRCODE = '22023';
    ELSIF FOUND AND v_diag_deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'VACANCY_REMOVED: Vacancy % is no longer active. It may have been removed or rolled back from an import batch.',
        v_app.vacancy_vcode
        USING ERRCODE = '22023';
    ELSE
      RAISE EXCEPTION 'VACANCY_NOT_FOUND: No active vacancy record found for %. Please refresh and try again.',
        v_app.vacancy_vcode
        USING ERRCODE = '22023';
    END IF;
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
  -- RETURNING * captures slot_id / coverage_slot_id / coverage_group_id for the
  -- Phase C (stationary) + Phase R-C (coverage) propagation below.
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
  -- v_app.slot_id (Phase B), v_app.coverage_slot_id / coverage_group_id (Phase R-B)
  -- now reflect the bound values (or NULL). Used in propagation below.

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
      -- First store: create roving master.
      -- Roving INSERT: no slot_id (roving carve-out — OHM2026_0044).
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
    IF v_hr.status = 'Moved to Plantilla' AND v_store_link_id IS NOT NULL THEN
      SELECT public.link_late_store_to_plantilla(v_store_link_id) INTO v_late_result;
    END IF;

  ELSE
    -- ── STATIONARY / COVERAGE: find or create HR Emploc ──────────────────────
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
      -- Phase C: propagate applicants.slot_id into hr_emploc.slot_id at INSERT.
      -- Phase R-C (OHM2026_0075): ALSO propagate applicants.coverage_slot_id +
      -- coverage_group_id (NULL for genuine stationary; set for coverage applicants,
      -- whose slot_id is NULL — the mutex CHECK keeps the two lineages disjoint).
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_id, vacancy_code_snapshot,
        account, account_id, chain_id, store_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        store_name, hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores,
        slot_id,            -- Phase C (OHM2026_0045): exact stationary slot; NULL for no-slot VCODEs
        coverage_slot_id,   -- Phase R-C (OHM2026_0075): exact coverage slot; NULL for stationary
        coverage_group_id   -- Phase R-C (OHM2026_0075): coverage group (query convenience); NULL for stationary
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.id, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.store_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.store_name, v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Stationary'::public.hr_emploc_assignment_type,
        NULL, '[]'::jsonb,
        v_app.slot_id,            -- Phase C: NULL when applicant has no bound stationary slot
        v_app.coverage_slot_id,   -- Phase R-C: NULL when applicant has no bound coverage slot
        v_app.coverage_group_id   -- Phase R-C: NULL when applicant has no coverage group
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

  -- ── Slot pipeline→hr_processing sync (routed by binding lineage) ──────────
  -- Phase R-C (OHM2026_0075) routes by the applicant's binding column. The mutex
  -- CHECK (RC2 / applicants_slot_coverage_mutex_chk) guarantees at most one of
  -- coverage_slot_id / slot_id is set, so the branches are disjoint.
  --
  --   coverage_slot_id IS NOT NULL → ROVING (Phase R-C): exact coverage slot
  --     pipeline→hr_processing via fn_sync_coverage_slot_to_hr_processing. NO
  --     coverage_group_id LIMIT 1, NO stationary VCODE LIMIT 1 on the carrier VCODE.
  --     Non-blocking — the helper NEVER raises (plan Q4).
  --   slot_id set / no slot (NOT v_is_roving) → STATIONARY (Phase C, UNCHANGED):
  --     fn_sync_slot_to_hr_processing with the exact slot (or legacy VCODE fallback).
  --   legacy roving (roving_assignment_id, NULL coverage_slot_id) → no slot sync
  --     (roving carve-out, unchanged).
  IF v_app.coverage_slot_id IS NOT NULL THEN
    PERFORM public.fn_sync_coverage_slot_to_hr_processing(
      p_coverage_slot_id => v_app.coverage_slot_id,
      p_applicant_id     => v_app.id,
      p_performed_by     => v_profile_id,
      p_source_fn        => 'confirm_applicant_onboard'
    );
  ELSIF NOT v_is_roving THEN
    PERFORM public.fn_sync_slot_to_hr_processing(
      p_vcode        => v_vac.vcode,
      p_applicant_id => v_app.id,
      p_performed_by => v_profile_id,
      p_source_fn    => 'confirm_applicant_onboard',
      p_slot_id      => v_app.slot_id   -- Phase C: exact slot; NULL → legacy path
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
  'OHM2026_0068: Source-agnostic — hc_request, migration/import, manual, and '
  'restored-import vacancies are treated identically (source column not checked). '
  'Controlled vacancy-not-found guard replaces raw P0002 exception: '
  'VACANCY_ARCHIVED (is_archived=true), VACANCY_REMOVED (deleted_at IS NOT NULL, '
  'e.g. rolled-back import), VACANCY_NOT_FOUND (missing row) — all ERRCODE 22023. '
  'Phase R-C (OHM2026_0075): copies applicants.coverage_slot_id + coverage_group_id '
  '→ hr_emploc at INSERT and drives the exact coverage slot pipeline→hr_processing via '
  'fn_sync_coverage_slot_to_hr_processing (no coverage_group_id LIMIT 1). '
  'Phase C (OHM2026_0045): copies applicants.slot_id → hr_emploc.slot_id and syncs the '
  'exact stationary slot pipeline→hr_processing (UNCHANGED). NULL on both lineages → '
  'legacy VCODE / roving path; onboard never blocked. Slot writes are non-blocking side '
  'effects (helpers never raise).';

-- GRANTs unchanged from RC phase
GRANT EXECUTE ON FUNCTION public.confirm_applicant_onboard(
  uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date
) TO authenticated;


-- ============================================================
-- Validation (manual)
-- ============================================================
-- V1 — Controlled error codes fired for inactive vacancies:
--   -- Simulate VACANCY_ARCHIVED:
--   UPDATE vacancies SET is_archived=true WHERE vcode='TEST_VCDG2_0005';
--   SELECT confirm_applicant_onboard('<applicant_id>');
--   -- Expected: error "VACANCY_ARCHIVED: Vacancy TEST_VCDG2_0005 has been archived..."
--
--   -- Simulate VACANCY_REMOVED (rollback):
--   UPDATE vacancies SET deleted_at=now() WHERE vcode='TEST_VCDG2_0005';
--   SELECT confirm_applicant_onboard('<applicant_id>');
--   -- Expected: error "VACANCY_REMOVED: Vacancy TEST_VCDG2_0005 is no longer active..."
--
--   -- Restore for normal flow:
--   UPDATE vacancies SET is_archived=false, deleted_at=NULL WHERE vcode='TEST_VCDG2_0005';
--   SELECT confirm_applicant_onboard('<applicant_id>');
--   -- Expected: success {"ok": true, ...}
--
-- V2 — HC Request vacancy approved normally (source='hc_request'):
--   SELECT confirm_applicant_onboard('<applicant_id_on_hc_request_vacancy>');
--   -- Expected: success — no source check in function
--
-- V3 — Import vacancy approved normally after batch approval (source='manual'):
--   SELECT confirm_applicant_onboard('<applicant_id_on_import_vacancy>');
--   -- Expected: success — identical treatment to HC Request
-- ============================================================
