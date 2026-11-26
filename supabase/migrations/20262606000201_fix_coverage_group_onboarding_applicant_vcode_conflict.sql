-- ============================================================================
-- Migration: 20262606000201_fix_coverage_group_onboarding_applicant_vcode_conflict.sql
-- Created: 2026-11-26T06:03:59.115Z
-- Description:
--   Hardens public.confirm_coverage_group_onboarding against duplicate key
--   violations on idx_applicants_no_active_duplicate:
--   - In Step 6, prevents overwriting vacancy_vcode of an existing applicant row
--     when onboarding a Coverage Group candidate.
--   - Preserves applicant's bound vacancy_vcode (e.g. secondary store VPSMG3_0016)
--     instead of forcibly clobbering it to the anchor store's vcode (v_first_selected_vcode).
--   - Falls back safely to coverage_code or v_first_selected_vcode only when vacancy_vcode
--     is NULL and no active duplicate exists.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.confirm_coverage_group_onboarding(
  p_applicant_id uuid,
  p_selected_store_ids uuid[],
  p_hired_by_user_id uuid DEFAULT NULL::uuid,
  p_hired_date date DEFAULT NULL::date,
  p_remarks text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role                 text    := public.get_my_role();
  v_role_level           int     := COALESCE(public.get_my_role_level(), 0);
  v_profile_id           uuid    := public.get_my_profile_id();
  v_actor_name           text    := public.get_my_full_name();
  v_app                  public.applicants%ROWTYPE;
  v_vac                  public.vacancies%ROWTYPE;
  v_group                public.coverage_groups%ROWTYPE;
  v_coverage_slot_id     uuid;
  v_hr                   public.hr_emploc%ROWTYPE;
  v_existing_plt         public.plantilla%ROWTYPE;
  v_hired_by_id          uuid;
  v_store_record         record;
  v_member_record        record;
  v_covered_json         jsonb   := '[]'::jsonb;
  v_store_id             uuid;
  v_store_names          text;
  v_first_selected_vcode text;
  v_first_selected_sid   uuid;
  v_first_selected_sname text;
  v_account_name         text;
  v_position_name        text;
  v_store_vac            public.vacancies%ROWTYPE;
  v_sibling_app_id       uuid;
  v_all_confirmed        boolean := true;
  v_target_slot          record;
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

  IF COALESCE(v_app.status, 'New') IN ('Failed', 'Backout', 'Did Not Report', 'Rejected by Ops') THEN
    RAISE EXCEPTION 'cannot onboard: applicant is in terminal status %', v_app.status USING ERRCODE = '22023';
  END IF;

  -- 2b. Auto-resolve coverage_group_id and coverage_slot_id from vacancy_vcode if not yet bound
  IF v_app.vacancy_vcode IS NOT NULL THEN
    SELECT * INTO v_vac
      FROM public.vacancies
     WHERE vcode = v_app.vacancy_vcode
       AND deleted_at IS NULL
     LIMIT 1;
  END IF;

  IF v_app.coverage_group_id IS NULL THEN
    SELECT cgs.coverage_group_id INTO v_app.coverage_group_id
      FROM public.coverage_group_stores cgs
      JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
      LEFT JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.archived_at IS NULL
       AND cg.archived_at IS NULL
       AND (
         (v_vac.store_id IS NOT NULL AND cgs.store_id = v_vac.store_id)
         OR (v_app.vacancy_vcode IS NOT NULL AND upper(s.vcode) = upper(v_app.vacancy_vcode))
         OR (v_app.vacancy_vcode IS NOT NULL AND upper(cg.coverage_code) = upper(v_app.vacancy_vcode))
       )
     ORDER BY cgs.is_anchor DESC, cgs.added_at ASC
     LIMIT 1;
  END IF;

  IF v_app.coverage_group_id IS NULL THEN
    RAISE EXCEPTION 'applicant is not assigned to a coverage group slot' USING ERRCODE = '22023';
  END IF;

  -- 3. Fetch and lock coverage group
  SELECT * INTO v_group FROM public.coverage_groups WHERE id = v_app.coverage_group_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage group not found' USING ERRCODE = 'P0002';
  END IF;

  v_coverage_slot_id := v_app.coverage_slot_id;
  IF v_coverage_slot_id IS NULL THEN
    SELECT cs.id INTO v_coverage_slot_id
      FROM public.coverage_slots cs
     WHERE cs.coverage_group_id = v_group.id
       AND COALESCE(cs.is_archived, false) = false
     ORDER BY
       CASE WHEN cs.slot_status IN ('pipeline', 'hr_processing') THEN 0 ELSE 1 END,
       cs.slot_ordinal ASC
     LIMIT 1;
  END IF;

  IF v_coverage_slot_id IS NULL THEN
    RAISE EXCEPTION 'coverage slot not found for coverage group %', v_group.coverage_code USING ERRCODE = '22023';
  END IF;

  -- 4. Scope Guard
  IF NOT public.i_have_full_access() AND NOT (v_group.account_id = ANY(public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: coverage group is outside caller scope' USING ERRCODE = '42501';
  END IF;

  IF array_length(p_selected_store_ids, 1) IS NULL OR array_length(p_selected_store_ids, 1) < 1 THEN
    RAISE EXCEPTION 'at least one store must be selected' USING ERRCODE = '22023';
  END IF;

  -- 5. Validate selected stores belong to coverage group and resolve primary selected store VCode
  FOR v_store_id IN SELECT DISTINCT unnest(p_selected_store_ids) LOOP
    SELECT s.id AS store_id, s.store_name, s.vcode, cgs.is_anchor INTO v_store_record
      FROM public.coverage_group_stores cgs
      JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.coverage_group_id = v_group.id
       AND cgs.store_id = v_store_id
       AND cgs.archived_at IS NULL;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'store % is not part of active coverage group footprint', v_store_id USING ERRCODE = '22023';
    END IF;

    IF v_first_selected_sid IS NULL OR v_store_record.is_anchor THEN
      v_first_selected_sid   := v_store_record.store_id;
      v_first_selected_sname := v_store_record.store_name;
      v_first_selected_vcode := v_store_record.vcode;
    END IF;
  END LOOP;

  SELECT account_name INTO v_account_name FROM public.accounts WHERE id = v_group.account_id;
  SELECT position_name INTO v_position_name FROM public.positions WHERE id = v_group.position_id;
  v_position_name := COALESCE(v_position_name, v_vac.position, 'MERCHANDISER');
  v_hired_by_id   := COALESCE(p_hired_by_user_id, v_profile_id);

  -- 6. Update primary applicant row (clear slot_id before setting coverage_slot_id to satisfy applicants_slot_coverage_mutex_chk)
  -- CRITICAL HARDENING: Do NOT clobber an existing applicant's vacancy_vcode (e.g. secondary store VPSMG3_0016)
  -- to v_first_selected_vcode (anchor store VPSMG3_0008), which triggers unique constraint violation
  -- on idx_applicants_no_active_duplicate when an active applicant row already exists for that name on the anchor store.
  UPDATE public.applicants
     SET status             = 'Confirmed Onboard',
         slot_id            = NULL,
         coverage_group_id  = v_group.id,
         coverage_slot_id   = v_coverage_slot_id,
         vacancy_vcode      = CASE
                                WHEN vacancy_vcode IS NOT NULL THEN vacancy_vcode
                                WHEN v_group.coverage_code IS NOT NULL AND NOT EXISTS (
                                  SELECT 1 FROM public.applicants d
                                   WHERE d.vacancy_vcode = v_group.coverage_code
                                     AND LOWER(TRIM(d.full_name)) = LOWER(TRIM(v_app.full_name))
                                     AND COALESCE(d.is_archived, false) = false
                                     AND d.id <> p_applicant_id
                                ) THEN v_group.coverage_code
                                WHEN v_first_selected_vcode IS NOT NULL AND NOT EXISTS (
                                  SELECT 1 FROM public.applicants d
                                   WHERE d.vacancy_vcode = v_first_selected_vcode
                                     AND LOWER(TRIM(d.full_name)) = LOWER(TRIM(v_app.full_name))
                                     AND COALESCE(d.is_archived, false) = false
                                     AND d.id <> p_applicant_id
                                ) THEN v_first_selected_vcode
                                ELSE vacancy_vcode
                              END,
         hired_date         = COALESCE(p_hired_date, hired_date, CURRENT_DATE),
         hired_at           = COALESCE(hired_at, NOW()),
         hired_by           = v_actor_name,
         hired_by_team      = v_role,
         hired_by_user_id   = v_hired_by_id,
         deployed_by_user_id = v_profile_id,
         remarks            = COALESCE(p_remarks, remarks),
         updated_at         = NOW(),
         updated_by         = v_profile_id
   WHERE id = p_applicant_id
   RETURNING * INTO v_app;

  -- Also mark any sibling pipeline applicant rows on selected stores as Confirmed Onboard
  UPDATE public.applicants a
     SET status              = 'Confirmed Onboard',
         slot_id             = NULL,
         coverage_group_id   = v_group.id,
         coverage_slot_id    = v_coverage_slot_id,
         hired_date          = COALESCE(p_hired_date, a.hired_date, CURRENT_DATE),
         hired_at            = COALESCE(a.hired_at, NOW()),
         hired_by            = v_actor_name,
         hired_by_team       = v_role,
         hired_by_user_id    = v_hired_by_id,
         deployed_by_user_id = v_profile_id,
         updated_at          = NOW(),
         updated_by          = v_profile_id
   WHERE a.id <> p_applicant_id
     AND COALESCE(a.is_archived, false) = false
     AND (
       a.coverage_group_id = v_group.id
       OR LOWER(TRIM(a.full_name)) = LOWER(TRIM(v_app.full_name))
     )
     AND EXISTS (
       SELECT 1 FROM public.stores s
       WHERE s.id = ANY(p_selected_store_ids)
         AND upper(s.vcode) = upper(a.vacancy_vcode)
     );

  -- ──────────────────────────────────────────────────────────────────────────
  -- 7. OPTION A: Check if candidate is ALREADY Active in Plantilla for this Account / Coverage Group
  --    (If already on duty with an Employee #, fast-track the newly confirmed store(s) directly to Plantilla!)
  -- ──────────────────────────────────────────────────────────────────────────
  SELECT plt.* INTO v_existing_plt
    FROM public.plantilla plt
   WHERE (plt.account_id = v_group.account_id OR plt.account = v_account_name)
     AND plt.status IN ('Active', 'On Leave')
     AND COALESCE(plt.is_deleted, false) = false
     AND COALESCE(plt.is_archived, false) = false
     AND plt.employee_no IS NOT NULL
     AND (
       plt.coverage_group_id = v_group.id
       OR plt.coverage_slot_id = v_coverage_slot_id
       OR LOWER(TRIM(plt.employee_name)) = LOWER(TRIM(v_app.full_name))
     )
   ORDER BY
     CASE WHEN plt.coverage_group_id = v_group.id THEN 0 ELSE 1 END,
     plt.created_at DESC
   LIMIT 1
  FOR UPDATE;

  IF v_existing_plt.id IS NOT NULL THEN
    -- Ensure Plantilla master is bound to this coverage group as Roving
    UPDATE public.plantilla
       SET deployment_type   = 'Roving',
           coverage_group_id = COALESCE(coverage_group_id, v_group.id),
           coverage_slot_id  = CASE WHEN roving_assignment_id IS NULL THEN COALESCE(coverage_slot_id, v_coverage_slot_id) ELSE coverage_slot_id END,
           updated_at        = NOW(),
           updated_by        = v_profile_id
     WHERE id = v_existing_plt.id
     RETURNING * INTO v_existing_plt;

    -- Also ensure the employee's primary store is in plantilla_store_links if not yet linked
    IF v_existing_plt.vcode IS NOT NULL AND NOT (v_existing_plt.vcode LIKE 'CG-%') THEN
      INSERT INTO public.plantilla_store_links (
        plantilla_id, roving_assignment_id, coverage_group_id,
        vacancy_id, vcode, store_name, account,
        status, linked_at, linked_by, created_by, updated_by
      ) VALUES (
        v_existing_plt.id, v_existing_plt.roving_assignment_id, v_group.id,
        v_existing_plt.vacancy_id, v_existing_plt.vcode,
        v_existing_plt.store_name, COALESCE(v_existing_plt.account, v_account_name),
        'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
      )
      ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL)
      DO UPDATE SET
        coverage_group_id = COALESCE(public.plantilla_store_links.coverage_group_id, EXCLUDED.coverage_group_id),
        status            = 'Active',
        unlinked_at       = NULL,
        unlinked_by       = NULL,
        updated_at        = NOW(),
        updated_by        = v_profile_id;
    END IF;

    -- Link each newly confirmed store into plantilla_store_links, close its vacancy, and occupy its plantilla_slot via fn_set_slot_status
    FOR v_store_id IN SELECT DISTINCT unnest(p_selected_store_ids) LOOP
      SELECT s.id AS store_id, s.store_name, s.vcode, cgs.is_anchor INTO v_store_record
        FROM public.coverage_group_stores cgs
        JOIN public.stores s ON s.id = cgs.store_id
       WHERE cgs.coverage_group_id = v_group.id
         AND cgs.store_id = v_store_id
         AND cgs.archived_at IS NULL;

      SELECT * INTO v_store_vac
        FROM public.vacancies
       WHERE (vcode = v_store_record.vcode OR store_id = v_store_id)
         AND deleted_at IS NULL
       ORDER BY CASE WHEN vcode = v_store_record.vcode THEN 0 ELSE 1 END, created_at DESC
       LIMIT 1;

      IF v_store_record.vcode IS NOT NULL THEN
        INSERT INTO public.plantilla_store_links (
          plantilla_id, roving_assignment_id, coverage_group_id,
          vacancy_id, vcode, store_name, account,
          status, linked_at, linked_by, created_by, updated_by
        ) VALUES (
          v_existing_plt.id, v_existing_plt.roving_assignment_id, v_group.id,
          v_store_vac.id, v_store_record.vcode,
          v_store_record.store_name, COALESCE(v_existing_plt.account, v_account_name),
          'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
        )
        ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL)
        DO UPDATE SET
          coverage_group_id = COALESCE(public.plantilla_store_links.coverage_group_id, EXCLUDED.coverage_group_id),
          status            = 'Active',
          unlinked_at       = NULL,
          unlinked_by       = NULL,
          updated_at        = NOW(),
          updated_by        = v_profile_id;

        -- Occupy physical plantilla_slot for this store via ADR-001 Rule 1 Slot Authority
        FOR v_target_slot IN
          SELECT id, slot_status
            FROM public.plantilla_slots
           WHERE legacy_vcode = v_store_record.vcode
             AND closed_at IS NULL
             AND slot_status IN ('open', 'pipeline', 'hr_processing')
        LOOP
          IF v_target_slot.slot_status = 'pipeline' THEN
            PERFORM public.fn_set_slot_status(
              p_slot_id               => v_target_slot.id,
              p_new_status            => 'hr_processing',
              p_reason_code           => 'REPLACEMENT',
              p_performed_by          => v_profile_id,
              p_remarks               => 'confirm_coverage_group_onboarding: Option A fast-track pipeline->hr_processing for ' || v_store_record.vcode,
              p_occupant_plantilla_id => NULL
            );
          END IF;

          PERFORM public.fn_set_slot_status(
            p_slot_id               => v_target_slot.id,
            p_new_status            => 'occupied',
            p_reason_code           => NULL,
            p_performed_by          => v_profile_id,
            p_remarks               => 'confirm_coverage_group_onboarding: Option A fast-track occupied by plantilla ' || v_existing_plt.id::text,
            p_occupant_plantilla_id => v_existing_plt.id
          );
        END LOOP;

        -- Close vacancy for this store
        UPDATE public.vacancies
           SET status     = 'Filled',
               updated_at = NOW(),
               updated_by = v_profile_id
         WHERE vcode = v_store_record.vcode
           AND deleted_at IS NULL
           AND status NOT IN ('Filled', 'Closed', 'Archived');
      END IF;

      -- Update hr_emploc_store_links if an hr_emploc record exists
      IF v_existing_plt.hr_emploc_id IS NOT NULL THEN
        UPDATE public.hr_emploc_store_links
           SET status       = 'Confirmed',
               confirmed_at = COALESCE(confirmed_at, NOW()),
               confirmed_by = COALESCE(confirmed_by, v_profile_id),
               updated_at   = NOW(),
               updated_by   = v_profile_id
         WHERE hr_emploc_id = v_existing_plt.hr_emploc_id
           AND (store_id = v_store_id OR vcode = v_store_record.vcode)
           AND deleted_at IS NULL;
      END IF;
    END LOOP;

    -- Rebalance employee_store_allocations (e.g. 0.50 SMCO ONEMALL + 0.50 SSM JAZZ)
    PERFORM public.fn_sync_employee_store_allocations(v_existing_plt.employee_no);

    -- Ensure coverage slot is active and bound to occupant
    UPDATE public.coverage_slots
       SET slot_status                   = 'active',
           current_occupant_plantilla_id = v_existing_plt.id,
           updated_at                    = NOW()
     WHERE id = v_coverage_slot_id;

    RETURN jsonb_build_object(
      'ok',                true,
      'fast_tracked',      true,
      'skipped_hr_emploc', true,
      'plantilla_id',      v_existing_plt.id,
      'employee_no',       v_existing_plt.employee_no,
      'coverage_group_id', v_group.id,
      'coverage_slot_id',  v_coverage_slot_id
    );
  END IF;

  -- ──────────────────────────────────────────────────────────────────────────
  -- 8. Check if an active (non-deployed) HR Emploc record ALREADY exists for this candidate / coverage slot
  -- ──────────────────────────────────────────────────────────────────────────
  SELECT * INTO v_hr
    FROM public.hr_emploc h
   WHERE h.deleted_at IS NULL
     AND h.status NOT IN ('Moved to Plantilla', 'Backout')
     AND (
       h.coverage_slot_id = v_coverage_slot_id
       OR h.coverage_group_id = v_group.id
       OR h.applicant_id = v_app.id
       OR (
         (h.account_id = v_group.account_id OR h.account = v_account_name)
         AND LOWER(TRIM(h.applicant_name)) = LOWER(TRIM(v_app.full_name))
       )
     )
   ORDER BY
     CASE WHEN h.coverage_slot_id = v_coverage_slot_id THEN 0 ELSE 1 END,
     h.created_at DESC
   LIMIT 1
  FOR UPDATE;

  -- Detach any prior separated occupant's terminal hr_emploc from this coverage_slot_id
  UPDATE public.hr_emploc
     SET deleted_at = NOW(),
         updated_by = v_profile_id
   WHERE coverage_slot_id = v_coverage_slot_id
     AND deleted_at IS NULL
     AND status = 'Moved to Plantilla'
     AND (v_hr.id IS NULL OR id <> v_hr.id);

  IF v_hr.id IS NULL THEN
    -- Insert new Coverage HR Emploc record
    INSERT INTO public.hr_emploc (
      applicant_name, applicant_name_snapshot, applicant_id,
      vcode, vacancy_id, vacancy_code_snapshot,
      account, account_id, store_id, store_name,
      position_id_snapshot, position,
      status, hr_status, hired_date,
      deployed_by_user_id, created_by, updated_by, date_requested,
      assignment_type, roving_assignment_id, slot_id,
      coverage_group_id, coverage_slot_id, covered_stores,
      ops_remarks, contact_number_snapshot
    ) VALUES (
      v_app.full_name, v_app.full_name, v_app.id,
      v_first_selected_vcode, NULL, v_group.coverage_code,
      v_account_name, v_group.account_id, v_first_selected_sid, v_first_selected_sname,
      v_group.position_id, v_position_name,
      'Pending Emploc', 'Pending', COALESCE(p_hired_date, v_app.hired_date, CURRENT_DATE),
      v_profile_id, v_profile_id, v_profile_id, NOW(),
      'Coverage'::public.hr_emploc_assignment_type, NULL, NULL,
      v_group.id, v_coverage_slot_id, '[]'::jsonb,
      p_remarks, v_app.contact_number
    )
    RETURNING * INTO v_hr;
  ELSE
    -- Upgrade existing hr_emploc to Coverage binding if it was created as Stationary on a single member store
    UPDATE public.hr_emploc
       SET assignment_type       = 'Coverage'::public.hr_emploc_assignment_type,
           vacancy_id            = NULL,
           roving_assignment_id  = NULL,
           slot_id               = NULL,
           coverage_group_id     = v_group.id,
           coverage_slot_id      = v_coverage_slot_id,
           vcode                 = COALESCE(vcode, v_first_selected_vcode),
           vacancy_code_snapshot = v_group.coverage_code,
           ops_remarks           = COALESCE(p_remarks, ops_remarks),
           updated_at            = NOW(),
           updated_by            = v_profile_id
     WHERE id = v_hr.id
     RETURNING * INTO v_hr;
  END IF;

  -- ──────────────────────────────────────────────────────────────────────────
  -- 9. Process ALL member stores of the Coverage Group (Selected vs. Unselected)
  -- ──────────────────────────────────────────────────────────────────────────
  FOR v_member_record IN
    SELECT cgs.store_id, cgs.is_anchor, cgs.hc_share, s.store_name, s.vcode
      FROM public.coverage_group_stores cgs
      JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.coverage_group_id = v_group.id
       AND cgs.archived_at IS NULL
     ORDER BY cgs.is_anchor DESC, s.store_name ASC
  LOOP
    SELECT * INTO v_store_vac
      FROM public.vacancies
     WHERE (vcode = v_member_record.vcode OR store_id = v_member_record.store_id)
       AND deleted_at IS NULL
     ORDER BY CASE WHEN vcode = v_member_record.vcode THEN 0 ELSE 1 END, created_at DESC
     LIMIT 1;

    IF v_member_record.store_id = ANY(p_selected_store_ids)
       OR EXISTS (
         SELECT 1 FROM public.hr_emploc_store_links hsl
         WHERE hsl.hr_emploc_id = v_hr.id
           AND hsl.store_id = v_member_record.store_id
           AND hsl.status = 'Confirmed'
           AND hsl.deleted_at IS NULL
       )
    THEN
      -- Store is CONFIRMED ONBOARD (selected now or already confirmed earlier)
      IF EXISTS (
        SELECT 1 FROM public.hr_emploc_store_links hsl
        WHERE hsl.hr_emploc_id = v_hr.id
          AND (hsl.store_id = v_member_record.store_id OR (v_member_record.vcode IS NOT NULL AND hsl.vcode = v_member_record.vcode))
          AND hsl.deleted_at IS NULL
      ) THEN
        UPDATE public.hr_emploc_store_links
           SET status            = 'Confirmed',
               coverage_group_id = v_group.id,
               coverage_slot_id  = v_coverage_slot_id,
               store_id          = v_member_record.store_id,
               vcode             = COALESCE(vcode, v_member_record.vcode),
               vacancy_id        = COALESCE(vacancy_id, v_store_vac.id),
               store_name        = v_member_record.store_name,
               confirmed_at      = COALESCE(confirmed_at, NOW()),
               confirmed_by      = COALESCE(confirmed_by, v_profile_id),
               updated_at        = NOW(),
               updated_by        = v_profile_id
         WHERE hr_emploc_id = v_hr.id
           AND (store_id = v_member_record.store_id OR (v_member_record.vcode IS NOT NULL AND vcode = v_member_record.vcode))
           AND deleted_at IS NULL;
      ELSE
        INSERT INTO public.hr_emploc_store_links (
          hr_emploc_id, coverage_group_id, coverage_slot_id, store_id,
          vacancy_id, vcode, store_name, account,
          status, confirmed_at, confirmed_by, created_by, updated_by
        ) VALUES (
          v_hr.id, v_group.id, v_coverage_slot_id, v_member_record.store_id,
          v_store_vac.id, v_member_record.vcode, v_member_record.store_name, v_hr.account,
          'Confirmed', NOW(), v_profile_id, v_profile_id, v_profile_id
        );
      END IF;

      -- Transition confirmed store's physical plantilla_slot to hr_processing via fn_set_slot_status
      IF v_member_record.vcode IS NOT NULL THEN
        FOR v_target_slot IN
          SELECT id
            FROM public.plantilla_slots
           WHERE legacy_vcode = v_member_record.vcode
             AND closed_at IS NULL
             AND slot_status IN ('open', 'pipeline')
        LOOP
          PERFORM public.fn_set_slot_status(
            p_slot_id               => v_target_slot.id,
            p_new_status            => 'hr_processing',
            p_reason_code           => 'REPLACEMENT',
            p_performed_by          => v_profile_id,
            p_remarks               => 'confirm_coverage_group_onboarding: store confirmed onboard for ' || v_member_record.vcode,
            p_occupant_plantilla_id => NULL
          );
        END LOOP;
      END IF;

      v_covered_json := v_covered_json || jsonb_build_object(
        'store_id',   v_member_record.store_id,
        'store_name', v_member_record.store_name,
        'vcode',      v_member_record.vcode,
        'is_anchor',  v_member_record.is_anchor,
        'status',     'Confirmed'
      );
    ELSE
      -- Store is UNSELECTED -> Keep in Pipeline ('For Requirements')!
      v_all_confirmed := false;

      IF NOT EXISTS (
        SELECT 1 FROM public.hr_emploc_store_links hsl
        WHERE hsl.hr_emploc_id = v_hr.id
          AND (hsl.store_id = v_member_record.store_id OR (v_member_record.vcode IS NOT NULL AND hsl.vcode = v_member_record.vcode))
          AND hsl.deleted_at IS NULL
      ) THEN
        INSERT INTO public.hr_emploc_store_links (
          hr_emploc_id, coverage_group_id, coverage_slot_id, store_id,
          vacancy_id, vcode, store_name, account,
          status, confirmed_at, confirmed_by, created_by, updated_by
        ) VALUES (
          v_hr.id, v_group.id, v_coverage_slot_id, v_member_record.store_id,
          v_store_vac.id, v_member_record.vcode, v_member_record.store_name, v_hr.account,
          'Pending', NULL, NULL, v_profile_id, v_profile_id
        );
      END IF;

      -- Ensure a linked pipeline applicant row ('For Requirements') exists on this remaining store's VCode
      IF v_member_record.vcode IS NOT NULL THEN
        SELECT a.id INTO v_sibling_app_id
          FROM public.applicants a
         WHERE a.vacancy_vcode = v_member_record.vcode
           AND COALESCE(a.is_archived, false) = false
           AND (
             a.coverage_group_id = v_group.id
             OR LOWER(TRIM(a.full_name)) = LOWER(TRIM(v_app.full_name))
           )
         ORDER BY a.created_at DESC
         LIMIT 1;

        IF v_sibling_app_id IS NULL THEN
          INSERT INTO public.applicants (
            vacancy_vcode,
            first_name, last_name, middle_name, full_name, full_name_snapshot,
            contact_number, status,
            coverage_group_id, coverage_slot_id,
            recruited_by_name, recruited_by_user_id,
            ops_remarks, is_archived, created_by, updated_by
          ) VALUES (
            v_member_record.vcode,
            v_app.first_name, v_app.last_name, v_app.middle_name, v_app.full_name, v_app.full_name,
            v_app.contact_number, 'For Requirements',
            v_group.id, v_coverage_slot_id,
            v_app.recruited_by_name, v_app.recruited_by_user_id,
            format('Remaining store for %s (Onboarded at %s)', v_group.coverage_code, COALESCE(v_first_selected_sname, 'Anchor Store')),
            false, v_profile_id, v_profile_id
          );
        ELSE
          UPDATE public.applicants
             SET status            = CASE WHEN status = 'Confirmed Onboard' THEN 'For Requirements' ELSE status END,
                 slot_id           = NULL,
                 coverage_group_id = v_group.id,
                 coverage_slot_id  = v_coverage_slot_id,
                 updated_at        = NOW(),
                 updated_by        = v_profile_id
           WHERE id = v_sibling_app_id;
        END IF;

        -- Keep remaining store's plantilla_slot in 'pipeline' via fn_set_slot_status
        FOR v_target_slot IN
          SELECT id
            FROM public.plantilla_slots
           WHERE legacy_vcode = v_member_record.vcode
             AND closed_at IS NULL
             AND slot_status = 'open'
        LOOP
          PERFORM public.fn_set_slot_status(
            p_slot_id               => v_target_slot.id,
            p_new_status            => 'pipeline',
            p_reason_code           => NULL,
            p_performed_by          => v_profile_id,
            p_remarks               => 'confirm_coverage_group_onboarding: remaining store kept in pipeline for ' || v_member_record.vcode,
            p_occupant_plantilla_id => NULL
          );
        END LOOP;
      END IF;

      v_covered_json := v_covered_json || jsonb_build_object(
        'store_id',   v_member_record.store_id,
        'store_name', v_member_record.store_name,
        'vcode',      v_member_record.vcode,
        'is_anchor',  v_member_record.is_anchor,
        'status',     'Pending Requirements'
      );
    END IF;
  END LOOP;

  -- Update hr_emploc covered_stores and store_name summary
  SELECT string_agg(el->>'store_name', ', ')
    INTO v_store_names
    FROM jsonb_array_elements(v_covered_json) el
   WHERE COALESCE(el->>'status', 'Confirmed') = 'Confirmed';

  UPDATE public.hr_emploc
     SET covered_stores = v_covered_json,
         store_name     = COALESCE(v_store_names, store_name),
         updated_at     = NOW(),
         updated_by     = v_profile_id
   WHERE id = v_hr.id
   RETURNING * INTO v_hr;

  -- 10. Transition coverage slot from pipeline -> hr_processing
  PERFORM public.fn_sync_coverage_slot_to_hr_processing(
    p_coverage_slot_id => v_coverage_slot_id,
    p_applicant_id     => v_app.id,
    p_performed_by     => v_profile_id,
    p_source_fn        => 'confirm_coverage_group_onboarding'
  );

  -- 11. Log activity
  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    v_app.full_name,
    v_group.coverage_code,
    'confirmed_onboard',
    'Coverage applicant confirmed onboard to ' || COALESCE(v_store_names, ''),
    v_actor_name,
    jsonb_build_object(
      'applicant_id',       v_app.id,
      'hr_emploc_id',       v_hr.id,
      'coverage_group_id',  v_group.id,
      'coverage_slot_id',   v_coverage_slot_id,
      'selected_stores',    v_covered_json,
      'all_confirmed',      v_all_confirmed
    )
  );

  RETURN jsonb_build_object(
    'ok',                true,
    'hr_emploc_id',      v_hr.id,
    'coverage_group_id', v_group.id,
    'coverage_slot_id',  v_coverage_slot_id,
    'all_confirmed',     v_all_confirmed
  );
END;
$function$;

COMMENT ON FUNCTION public.confirm_coverage_group_onboarding(uuid, uuid[], uuid, date, text) IS
  'Confirms a candidate for an entire Coverage Group footprint or subset of member stores. Unselected stores remain open in pipeline.';
REVOKE ALL ON FUNCTION public.confirm_coverage_group_onboarding(uuid, uuid[], uuid, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_coverage_group_onboarding(uuid, uuid[], uuid, date, text) TO authenticated;

COMMIT;
