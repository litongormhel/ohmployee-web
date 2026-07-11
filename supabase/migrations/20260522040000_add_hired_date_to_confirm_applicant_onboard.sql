-- Migration: add p_hired_date to confirm_applicant_onboard
-- OHM2026_2059
--
-- Problem:
--   Flutter now passes p_hired_date (date) as the official hiring date for
--   closure/timeline metrics.  The existing function lacks this parameter so
--   the call fails with "unknown named parameter".
--
-- Change (surgical):
--   1. Add parameter  p_hired_date date DEFAULT NULL::date
--   2. In UPDATE applicants, change
--        hired_date = COALESCE(hired_date, CURRENT_DATE)
--      to
--        hired_date = COALESCE(p_hired_date, hired_date, CURRENT_DATE)
--      so that the caller-supplied date takes precedence over any existing
--      value and falls back to today only when both are absent.
--   3. hired_at remains COALESCE(hired_at, NOW()) — it is the confirmation
--      action timestamp, not the metric date.
--   4. All hr_emploc INSERTs already read hired_date from v_app (populated
--      via RETURNING * after the UPDATE), so they automatically receive the
--      resolved p_hired_date with no further changes.
--
-- Everything else — parameters, RBAC, idempotency guard, roving logic,
-- fast-track branches, store-link management, audit log, return shape,
-- SECURITY DEFINER, GRANT — is preserved identically.
--
-- Validation (run after apply):
--   SELECT proname, pg_get_function_identity_arguments(oid)
--     FROM pg_proc
--    WHERE proname = 'confirm_applicant_onboard'
--      AND pronamespace = 'public'::regnamespace;
--   -- Must show p_hired_date date in the argument list.

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

-- Preserve existing permission grant
GRANT EXECUTE ON FUNCTION public.confirm_applicant_onboard(
  uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date
) TO authenticated;

-- ── Validation ────────────────────────────────────────────────────────────────
-- Run after applying this migration to confirm the signature is correct:
--
-- SELECT proname,
--        pg_get_function_identity_arguments(oid) AS args
--   FROM pg_proc
--  WHERE proname = 'confirm_applicant_onboard'
--    AND pronamespace = 'public'::regnamespace;
--
-- Expected: exactly one row; args includes "p_hired_date date".
--
-- Cross-check Flutter call parameters (all named, order-independent):
--   p_applicant_id             uuid      ✓ present
--   p_contact_number           text      ✓ present (DEFAULT NULL)
--   p_endorsed_by_deployer_id  uuid      ✓ present (DEFAULT NULL)
--   p_endorsed_by_name         text      ✓ present (DEFAULT NULL)
--   p_first_name               text      ✓ present (DEFAULT NULL)
--   p_full_name                text      ✓ present (DEFAULT NULL)
--   p_hired_by_user_id         uuid      ✓ present (DEFAULT NULL)
--   p_hired_date               date      ✓ NEW — added by this migration
--   p_last_name                text      ✓ present (DEFAULT NULL)
--   p_middle_name              text      ✓ present (DEFAULT NULL)
--   p_remarks                  text      ✓ present (DEFAULT NULL)
--   p_roving_assignment_id     uuid      ✓ present (DEFAULT NULL)
