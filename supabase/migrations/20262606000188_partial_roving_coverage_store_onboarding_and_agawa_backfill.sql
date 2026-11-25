-- ============================================================================
-- Migration: 20262606000188_partial_roving_coverage_store_onboarding_and_agawa_backfill.sql
-- Created: 2026-11-25T12:27:00.000Z
-- Description:
-- 1. Partial / Staggered Roving Coverage Group Store Onboarding (Web & Mobile Parity):
--    - Updates fn_assert_applicant_duplicate_and_reuse and check_candidate_duplicate
--      to allow an active pipeline applicant row on a remaining member store of the
--      same Coverage Group (coverage_group_id) or Roving Assignment (roving_assignment_id)
--      when the same candidate has already onboarded at another member store (in hr_emploc
--      or active in plantilla).
--    - Hardens confirm_coverage_group_onboarding:
--      * Auto-resolves coverage_group_id & coverage_slot_id from store VCode if not pre-bound.
--      * Supports partial store selection (p_selected_store_ids): selected stores transition
--        to Confirmed Onboard / hr_emploc (or fast-track to Active Plantilla under Option A if
--        the candidate is already deployed at the first store), while unselected member stores
--        stay in Pipeline ('For Requirements') with a linked applicant row on their store VCode.
--      * When the remaining store completes requirements later:
--        - If candidate is still in HR Emploc: merges the newly confirmed store into the
--          existing hr_emploc record (updating hr_emploc_store_links & covered_stores).
--        - If candidate is already Active in Plantilla (Option A Fast-Track): links the store
--          directly into plantilla_store_links, occupies the store's plantilla_slots row, closes
--          the store's vacancy, and rebalances employee_store_allocations (e.g. 0.50 + 0.50 HC).
--    - Hardens confirm_applicant_onboard (13-arg):
--      * When called on a store belonging to a Coverage Group (initial or remaining store),
--        delegates to confirm_coverage_group_onboarding for that store.
--    - Hardens _assign_and_deploy_emploc_core:
--      * Supports Coverage Group (coverage_slot_id IS NOT NULL) and Roving deployments,
--        inserting plantilla_store_links for all Confirmed stores in hr_emploc_store_links,
--        occupying their plantilla_slots, closing confirmed store vacancies, and syncing
--        employee_store_allocations.
-- 2. Updates v_account_allocation_kpi (preserving all 19 columns in exact order) so a candidate
--    partially onboarded across a Coverage Group is never double-counted in pipeline_count or
--    required_hc.
-- 3. Backfills AGAWA, BERNARDINO OPENARIA in PERFECT SM (CG-PG3-0001):
--    - Binds SMCO ONEMALL (VPSMG3_0008) to CG-PG3-0001 as Confirmed Onboard in HR Emploc.
--    - Creates the linked pipeline applicant row for SSM JAZZ (VPSMG3_0016) with status
--      'For Requirements' so SSM JAZZ remains actionable in the Vacancy & Plantilla Pipeline.
-- ============================================================================

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Update fn_assert_applicant_duplicate_and_reuse (Allow same Coverage Group / Roving sibling store)
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_assert_applicant_duplicate_and_reuse()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_first             text;
  v_last              text;
  v_contact           text;
  v_conflict_vcode    text;
  v_conflict_store    text;
  v_conflict_account  text;
  v_conflict_status   text;
BEGIN
  -- Only enforce when the resulting row is an ACTIVE, non-archived applicant.
  IF COALESCE(NEW.is_archived, false) = true
     OR NOT public.fn_is_active_vacancy_applicant_status(NEW.status) THEN
    RETURN NEW;
  END IF;

  -- Normalise identity components.
  v_last    := lower(btrim(COALESCE(NEW.last_name, '')));
  v_first   := lower(btrim(COALESCE(NEW.first_name, '')));
  v_contact := public.fn_clean_mobile_number(NEW.contact_number);

  -- Incomplete identity -> cannot reliably match a person -> skip.
  IF v_last = '' OR v_first = '' OR v_contact IS NULL OR v_contact = '' THEN
    RETURN NEW;
  END IF;

  -- 1. Check against active pipeline applicants in applicants table
  --    (Exclude sibling store rows belonging to the same coverage_group_id or roving_assignment_id)
  SELECT a2.vacancy_vcode, COALESCE(v2.store_name, 'N/A'), COALESCE(v2.account, 'N/A'), a2.status
    INTO v_conflict_vcode, v_conflict_store, v_conflict_account, v_conflict_status
  FROM public.applicants a2
  LEFT JOIN public.vacancies v2 ON v2.vcode = a2.vacancy_vcode AND v2.deleted_at IS NULL
  WHERE a2.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
    AND COALESCE(a2.is_archived, false) = false
    AND public.fn_is_active_vacancy_applicant_status(a2.status)
    AND lower(btrim(COALESCE(a2.last_name, '')))  = v_last
    AND lower(btrim(COALESCE(a2.first_name, ''))) = v_first
    AND public.fn_clean_mobile_number(a2.contact_number) = v_contact
    AND NOT (NEW.coverage_group_id IS NOT NULL AND a2.coverage_group_id = NEW.coverage_group_id)
    AND NOT (NEW.roving_assignment_id IS NOT NULL AND a2.roving_assignment_id = NEW.roving_assignment_id)
  ORDER BY a2.created_at DESC
  LIMIT 1;

  IF v_conflict_vcode IS NOT NULL THEN
    RAISE EXCEPTION
      'Candidate is already active in Pipeline (Status: %, VCode: %, Store: %, Account: %). Duplicate creation is blocked.'
      , v_conflict_status, v_conflict_vcode, v_conflict_store, v_conflict_account
      USING
        DETAIL = format('Active VCode: %s, Store: %s, Account: %s', v_conflict_vcode, v_conflict_store, v_conflict_account),
        ERRCODE = '23505';
  END IF;

  -- 2. Check against active candidates in HR Emploc
  --    (Exclude same coverage_group_id or roving_assignment_id for staggered multi-store onboarding)
  SELECT COALESCE(h.vcode, 'N/A'), COALESCE(h.store_name, 'N/A'), COALESCE(h.account, 'N/A'), h.status
    INTO v_conflict_vcode, v_conflict_store, v_conflict_account, v_conflict_status
  FROM public.hr_emploc h
  LEFT JOIN public.applicants a ON a.id = h.applicant_id
  WHERE h.deleted_at IS NULL
    AND h.status NOT IN ('Moved to Plantilla', 'Rejected', 'Backout', 'Cancelled')
    AND NOT (NEW.coverage_group_id IS NOT NULL AND h.coverage_group_id = NEW.coverage_group_id)
    AND NOT (NEW.roving_assignment_id IS NOT NULL AND h.roving_assignment_id = NEW.roving_assignment_id)
    AND (
      (
        a.id IS NOT NULL
        AND lower(btrim(COALESCE(a.last_name, ''))) = v_last
        AND lower(btrim(COALESCE(a.first_name, ''))) = v_first
        AND public.fn_clean_mobile_number(a.contact_number) = v_contact
      )
      OR
      (
        public.fn_clean_mobile_number(h.contact_number_snapshot) = v_contact
        AND lower(btrim(h.applicant_name)) LIKE '%' || v_last || '%'
        AND lower(btrim(h.applicant_name)) LIKE '%' || v_first || '%'
      )
    )
  ORDER BY h.created_at DESC
  LIMIT 1;

  IF v_conflict_vcode IS NOT NULL THEN
    RAISE EXCEPTION
      'Candidate is already active in HR Emploc processing (Status: %, VCode: %, Store: %, Account: %). Duplicate creation is blocked.'
      , v_conflict_status, v_conflict_vcode, v_conflict_store, v_conflict_account
      USING
        DETAIL = format('HR Emploc VCode: %s, Store: %s, Account: %s', v_conflict_vcode, v_conflict_store, v_conflict_account),
        ERRCODE = '23505';
  END IF;

  -- 3. Check against Active Plantilla employees (unless creating an authorized Plantilla Additional Store or Coverage Group sibling store)
  IF COALESCE(NEW.applicant_source, '') <> 'plantilla' AND NEW.linked_plantilla_id IS NULL THEN
    SELECT COALESCE(p.vcode, 'N/A'), COALESCE(p.store_name, 'N/A'), COALESCE(p.account, 'N/A'), p.status
      INTO v_conflict_vcode, v_conflict_store, v_conflict_account, v_conflict_status
    FROM public.plantilla p
    WHERE p.status = 'Active'
      AND COALESCE(p.is_deleted, false) = false
      AND NOT (NEW.coverage_group_id IS NOT NULL AND p.coverage_group_id = NEW.coverage_group_id)
      AND NOT (NEW.roving_assignment_id IS NOT NULL AND p.roving_assignment_id = NEW.roving_assignment_id)
      AND (
        (
          lower(btrim(COALESCE(p.last_name, ''))) = v_last
          AND lower(btrim(COALESCE(p.first_name, ''))) = v_first
          AND public.fn_clean_mobile_number(p.contact_no) = v_contact
        )
        OR
        (
          public.fn_clean_mobile_number(p.contact_no) = v_contact
          AND lower(btrim(p.employee_name)) LIKE '%' || v_last || '%'
          AND lower(btrim(p.employee_name)) LIKE '%' || v_first || '%'
        )
      )
    ORDER BY p.created_at DESC
    LIMIT 1;

    IF v_conflict_vcode IS NOT NULL THEN
      RAISE EXCEPTION
        'Candidate is already an Active employee in Plantilla (VCode: %, Store: %, Account: %). Duplicate creation is blocked.'
        , v_conflict_vcode, v_conflict_store, v_conflict_account
        USING
          DETAIL = format('Plantilla VCode: %s, Store: %s, Account: %s', v_conflict_vcode, v_conflict_store, v_conflict_account),
          ERRCODE = '23505';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;


-- ────────────────────────────────────────────────────────────────────────────
-- 2. Harden confirm_coverage_group_onboarding (Partial Store Selection + Late Store Merge + Option A Fast-Track)
-- ────────────────────────────────────────────────────────────────────────────
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
  UPDATE public.applicants
     SET status             = 'Confirmed Onboard',
         slot_id            = NULL,
         coverage_group_id  = v_group.id,
         coverage_slot_id   = v_coverage_slot_id,
         vacancy_vcode      = COALESCE(v_first_selected_vcode, vacancy_vcode),
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

    -- Link each newly confirmed store into plantilla_store_links, close its vacancy, and occupy its plantilla_slot
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

        -- Occupy physical plantilla_slot for this store
        UPDATE public.plantilla_slots
           SET slot_status                   = 'occupied',
               current_occupant_plantilla_id = v_existing_plt.id,
               updated_at                    = NOW(),
               updated_by                    = v_profile_id
         WHERE legacy_vcode = v_store_record.vcode
           AND closed_at IS NULL
           AND slot_status IN ('open', 'pipeline', 'hr_processing');

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

      -- Transition confirmed store's physical plantilla_slot to hr_processing
      IF v_member_record.vcode IS NOT NULL THEN
        UPDATE public.plantilla_slots
           SET slot_status = 'hr_processing',
               updated_at  = NOW(),
               updated_by  = v_profile_id
         WHERE legacy_vcode = v_member_record.vcode
           AND closed_at IS NULL
           AND slot_status IN ('open', 'pipeline');
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

        -- Keep remaining store's plantilla_slot in 'pipeline' and vacancy 'Open'
        UPDATE public.plantilla_slots
           SET slot_status = 'pipeline',
               updated_at  = NOW(),
               updated_by  = v_profile_id
         WHERE legacy_vcode = v_member_record.vcode
           AND closed_at IS NULL
           AND slot_status = 'open';
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


-- ────────────────────────────────────────────────────────────────────────────
-- 3. Harden confirm_applicant_onboard (13-arg) to Delegate Coverage Group / Remaining Store Onboarding
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.confirm_applicant_onboard(
  p_applicant_id uuid,
  p_last_name text DEFAULT NULL::text,
  p_first_name text DEFAULT NULL::text,
  p_middle_name text DEFAULT NULL::text,
  p_full_name text DEFAULT NULL::text,
  p_contact_number text DEFAULT NULL::text,
  p_remarks text DEFAULT NULL::text,
  p_roving_assignment_id uuid DEFAULT NULL::uuid,
  p_hired_by_user_id uuid DEFAULT NULL::uuid,
  p_endorsed_by_deployer_id uuid DEFAULT NULL::uuid,
  p_endorsed_by_name text DEFAULT NULL::text,
  p_hired_date date DEFAULT NULL::date,
  p_vacancy_requirement_id uuid DEFAULT NULL::uuid
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
  v_existing_plt      public.plantilla%ROWTYPE;
  v_roving_id         uuid;
  v_new_roving        boolean := false;
  v_plt_store_link_id uuid;
  v_existing_employee_no text;
  v_roving_hr_found   boolean := false;
  v_resolved_requirement_id uuid;
  v_slot_sync_result  jsonb;
  v_cg_store_id       uuid;
BEGIN
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Data Team, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

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
      'applicant % has terminal status % — cannot onboard',
      p_applicant_id, v_app.status
      USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_vac
    FROM public.vacancies
   WHERE vcode = v_app.vacancy_vcode
     AND deleted_at IS NULL
   LIMIT 1;

  -- If applicant is bound to a Coverage Group (e.g. remaining store SSM JAZZ completing requirements),
  -- delegate directly to confirm_coverage_group_onboarding for this store!
  IF v_app.coverage_group_id IS NOT NULL THEN
    v_cg_store_id := v_vac.store_id;
    IF v_cg_store_id IS NULL AND v_app.vacancy_vcode IS NOT NULL THEN
      SELECT s.id INTO v_cg_store_id
        FROM public.stores s
       WHERE upper(s.vcode) = upper(v_app.vacancy_vcode)
       LIMIT 1;
    END IF;

    IF v_cg_store_id IS NOT NULL THEN
      RETURN public.confirm_coverage_group_onboarding(
        p_applicant_id       => p_applicant_id,
        p_selected_store_ids => ARRAY[v_cg_store_id],
        p_hired_by_user_id   => p_hired_by_user_id,
        p_hired_date         => p_hired_date,
        p_remarks            => p_remarks
      );
    END IF;
  END IF;

  IF v_vac.id IS NULL THEN
    RAISE EXCEPTION 'vacancy % not found', v_app.vacancy_vcode
      USING ERRCODE = 'P0002';
  END IF;

  v_is_roving := COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL;

  -- ── Idempotent Guard ──
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

  -- Resolve requirement ID
  v_resolved_requirement_id := COALESCE(p_vacancy_requirement_id, v_app.vacancy_requirement_id);

  IF v_resolved_requirement_id IS NULL AND NOT v_is_roving THEN
    SELECT vr.id INTO v_resolved_requirement_id
      FROM public.vacancy_requirements vr
     WHERE vr.vacancy_id = v_vac.id
       AND GREATEST(
             (SELECT count(*) FROM public.plantilla p
               WHERE p.vacancy_requirement_id = vr.id
                 AND p.status = 'Active'
                 AND COALESCE(p.is_deleted, false) = false),
             (SELECT count(*) FROM public.applicants a
               WHERE a.vacancy_requirement_id = vr.id
                 AND a.status = 'Confirmed Onboard'
                 AND COALESCE(a.is_archived, false) = false
                 AND a.id <> p_applicant_id)
           ) < vr.hc_needed
     ORDER BY vr.created_at
     LIMIT 1;

    IF v_resolved_requirement_id IS NULL THEN
      SELECT id INTO v_resolved_requirement_id
        FROM public.vacancy_requirements
       WHERE vacancy_id = v_vac.id
       ORDER BY created_at
       LIMIT 1;
    END IF;
  END IF;

  IF p_hired_by_user_id IS NOT NULL THEN
    v_hired_by_id := p_hired_by_user_id;
  ELSE
    v_hired_by_id := public.get_my_auth_uid();
  END IF;

  UPDATE public.applicants
     SET status               = 'Confirmed Onboard',
         last_name            = COALESCE(p_last_name,      last_name),
         first_name           = COALESCE(p_first_name,     first_name),
         middle_name          = COALESCE(p_middle_name,    middle_name),
         full_name            = COALESCE(p_full_name,      full_name),
         contact_number       = COALESCE(p_contact_number, contact_number),
         remarks              = COALESCE(p_remarks,        remarks),
         hired_date           = COALESCE(p_hired_date,     hired_date),
         hired_by             = v_hired_by_id::text,
         roving_assignment_id = COALESCE(
                                  p_roving_assignment_id,
                                  roving_assignment_id
                                ),
         vacancy_requirement_id = COALESCE(
                                    v_resolved_requirement_id,
                                    vacancy_requirement_id
                                  ),
         last_activity_at     = NOW(),
         last_activity_by     = v_profile_id,
         updated_at           = NOW()
   WHERE id = p_applicant_id;

  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id;

  -- Option A Fast-Track for existing Active Plantilla employee in same account
  SELECT plt.* INTO v_existing_plt
    FROM public.plantilla plt
   WHERE plt.account = v_vac.account
     AND (
       plt.employee_no ILIKE v_app.full_name
       OR LOWER(TRIM(plt.employee_name)) = LOWER(TRIM(v_app.full_name))
     )
     AND plt.status IN ('Active', 'On Leave')
     AND NOT COALESCE(plt.is_deleted, false)
     AND NOT COALESCE(plt.is_archived, false)
     AND plt.employee_no IS NOT NULL
   LIMIT 1
  FOR UPDATE;

  IF v_existing_plt.id IS NOT NULL THEN
    v_roving_id := COALESCE(v_existing_plt.roving_assignment_id, p_roving_assignment_id, v_app.roving_assignment_id);
    IF v_roving_id IS NULL AND v_existing_plt.coverage_slot_id IS NULL THEN
      INSERT INTO public.roving_assignments (
        master_applicant_id, account, account_id,
        primary_vcode, label, created_by, updated_by
      ) VALUES (
        v_app.id, v_vac.account, v_vac.account_id,
        COALESCE(v_existing_plt.vcode, v_vac.vcode),
        v_app.full_name,
        v_profile_id, v_profile_id
      )
      RETURNING id INTO v_roving_id;
    END IF;

    UPDATE public.plantilla
       SET deployment_type      = 'Roving',
           roving_assignment_id = CASE WHEN coverage_slot_id IS NULL THEN COALESCE(roving_assignment_id, v_roving_id) ELSE roving_assignment_id END,
           updated_at           = NOW(),
           updated_by           = v_profile_id
     WHERE id = v_existing_plt.id
     RETURNING * INTO v_existing_plt;

    IF v_existing_plt.vcode IS NOT NULL AND NOT (v_existing_plt.vcode LIKE 'CG-%') THEN
      INSERT INTO public.plantilla_store_links (
        plantilla_id, roving_assignment_id, coverage_group_id,
        vacancy_id, vcode, store_name, account,
        status, linked_at, linked_by, created_by, updated_by
      ) VALUES (
        v_existing_plt.id, v_existing_plt.roving_assignment_id, v_existing_plt.coverage_group_id,
        v_existing_plt.vacancy_id, v_existing_plt.vcode,
        v_existing_plt.store_name, v_existing_plt.account,
        'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
      )
      ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL) DO NOTHING;
    END IF;

    INSERT INTO public.plantilla_store_links (
      plantilla_id, roving_assignment_id, coverage_group_id,
      vacancy_id, vcode, store_name, account,
      status, linked_at, linked_by, created_by, updated_by
    ) VALUES (
      v_existing_plt.id, v_existing_plt.roving_assignment_id, v_existing_plt.coverage_group_id,
      v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
      'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
    )
    ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL)
    DO UPDATE SET
      status      = 'Active',
      unlinked_at = NULL,
      unlinked_by = NULL,
      updated_at  = NOW(),
      updated_by  = v_profile_id
    RETURNING id INTO v_plt_store_link_id;

    UPDATE public.plantilla_slots
       SET slot_status                   = 'occupied',
           current_occupant_plantilla_id = v_existing_plt.id,
           updated_at                    = NOW(),
           updated_by                    = v_profile_id
     WHERE legacy_vcode = v_vac.vcode
       AND closed_at IS NULL
       AND slot_status IN ('open', 'pipeline', 'hr_processing');

    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_profile_id
     WHERE id = v_vac.id;

    PERFORM public.fn_sync_employee_store_allocations(v_existing_plt.employee_no);

    RETURN jsonb_build_object(
      'ok',                      true,
      'applicant_id',            v_app.id,
      'applicant_status',        v_app.status,
      'hr_emploc_id',            NULL,
      'plantilla_id',            v_existing_plt.id,
      'plantilla_store_link_id', v_plt_store_link_id,
      'vcode',                   v_vac.vcode,
      'hired_by_user_id',        v_hired_by_id,
      'is_roving',               true,
      'fast_tracked',            true,
      'skipped_hr_emploc',       true
    );
  END IF;

  SELECT * INTO v_hr
    FROM public.hr_emploc
   WHERE applicant_id = p_applicant_id
     AND deleted_at IS NULL
   LIMIT 1;

  IF v_hr.id IS NOT NULL THEN
    UPDATE public.hr_emploc
       SET hr_status              = COALESCE(hr_status, 'Pending'),
           vacancy_requirement_id = COALESCE(vacancy_requirement_id, v_resolved_requirement_id),
           updated_at             = NOW()
      WHERE id = v_hr.id
     RETURNING * INTO v_hr;
  ELSE
    IF NOT v_is_roving THEN
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_id, vacancy_code_snapshot,
        account, account_id, chain_id, store_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        store_name, hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores,
        vacancy_requirement_id
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
        v_resolved_requirement_id
      )
      RETURNING * INTO v_hr;
    END IF;
  END IF;

  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    COALESCE(v_hr.emploc_no, v_app.full_name),
    v_vac.vcode,
    'confirmed_onboard',
    'Applicant confirmed onboard and moved to HR Emploc for ' || v_vac.vcode,
    v_actor_name,
    jsonb_build_object(
      'applicant_id',               v_app.id,
      'hr_emploc_id',               v_hr.id,
      'vacancy_id',                 v_vac.id,
      'role',                       v_role,
      'hired_by_user_id',           v_hired_by_id,
      'endorsed_by_deployer_id',    p_endorsed_by_deployer_id,
      'endorsed_by_name',           p_endorsed_by_name,
      'is_roving',                  v_is_roving,
      'hired_date',                 v_app.hired_date,
      'late_store_linked',          v_late_result IS NOT NULL,
      'vacancy_requirement_id',     v_resolved_requirement_id,
      'movement_at',                NOW()
    )
  );

  IF v_resolved_requirement_id IS NOT NULL THEN
    IF p_vacancy_requirement_id IS NOT NULL THEN
      IF EXISTS (
        SELECT 1 FROM public.vacancy_requirements vr
         WHERE vr.id = p_vacancy_requirement_id
           AND GREATEST(
                 (SELECT count(*) FROM public.plantilla p
                   WHERE p.vacancy_requirement_id = vr.id
                     AND p.status = 'Active'
                     AND COALESCE(p.is_deleted, false) = false),
                 (SELECT count(*) FROM public.applicants a
                   WHERE a.vacancy_requirement_id = vr.id
                     AND a.status = 'Confirmed Onboard'
                     AND COALESCE(a.is_archived, false) = false
                     AND a.id <> p_applicant_id)
               ) >= vr.hc_needed
      ) THEN
        RAISE EXCEPTION 'requirement_already_full'
          USING MESSAGE = 'The selected position requirement has no remaining headcount. Another hire may have filled it concurrently.',
                HINT    = 'Refresh the vacancy and select a different requirement.';
      END IF;
    END IF;
  END IF;

  IF NOT v_is_roving THEN
    v_slot_sync_result := public.fn_sync_slot_to_hr_processing(
      p_vcode        => v_vac.vcode,
      p_applicant_id => v_app.id,
      p_performed_by => v_profile_id,
      p_source_fn    => 'confirm_applicant_onboard',
      p_slot_id      => v_app.slot_id
    );

    IF v_hr.id IS NOT NULL AND (v_slot_sync_result->>'slot_id') IS NOT NULL AND v_hr.coverage_slot_id IS NULL THEN
      UPDATE public.hr_emploc
         SET slot_id = (v_slot_sync_result->>'slot_id')::uuid
       WHERE id = v_hr.id
         AND slot_id IS NULL;

      UPDATE public.applicants
         SET slot_id = (v_slot_sync_result->>'slot_id')::uuid
       WHERE id = v_app.id
         AND slot_id IS NULL
         AND coverage_slot_id IS NULL;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok',                       true,
    'applicant_id',             v_app.id,
    'applicant_status',         v_app.status,
    'hr_emploc_id',             v_hr.id,
    'vcode',                    v_vac.vcode,
    'hired_by_user_id',         v_hired_by_id,
    'hired_date',               v_app.hired_date,
    'is_roving',                v_is_roving,
    'late_store_linked',        v_late_result,
    'vacancy_requirement_id',   v_resolved_requirement_id
  );
END;
$function$;


-- ────────────────────────────────────────────────────────────────────────────
-- 4. Harden _assign_and_deploy_emploc_core (Support Coverage Group & Roving Store Link Sync)
-- ────────────────────────────────────────────────────────────────────────────
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
  IF p_source_fn = 'assign_hr_emploc_number' THEN
    IF v_emp.hr_status = 'Pending' THEN
      IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'INVALID_STATE_FOR_ASSIGN: Record must be in "For Emploc" status before assigning an Employee ID (current hr_status: "Pending"). Ops must upload and submit requirements first.'
          USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STATE_FOR_ASSIGN')::text;
      END IF;
    ELSIF v_emp.hr_status NOT IN ('For Emploc', 'Complete') AND v_emp.status <> 'Moved to Plantilla' THEN
      RAISE EXCEPTION 'INVALID_STATE_FOR_ASSIGN: Cannot assign Employee ID from hr_status "%". Expected "For Emploc".', v_emp.hr_status
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

  IF COALESCE(v_emp.assignment_type::text, 'Stationary') NOT IN ('Roving', 'Coverage') AND v_emp.coverage_slot_id IS NULL THEN
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

  -- 6. SLOT SELECTION AND RESERVATION (Stationary non-pool non-roving)
  IF v_emp.vacancy_id IS NOT NULL THEN
    SELECT v.is_pool_vacancy, v.pool_type_id, v.home_account_id
      INTO v_is_pool, v_pool_type_id, v_home_account_id
      FROM vacancies v
     WHERE v.id = v_emp.vacancy_id;
  END IF;
  v_is_pool := COALESCE(v_is_pool, false);

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
    SELECT * INTO v_home_acct FROM accounts WHERE id = v_home_account_id;

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
      v_home_acct.account_name, v_home_acct.id,
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


-- ────────────────────────────────────────────────────────────────────────────
-- 5. Update v_account_allocation_kpi (Deduplicate Partial Roving Coverage Group Candidates)
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_account_allocation_kpi
  WITH (security_invoker = true)
AS
WITH filled AS (
  SELECT a.account_id,
         round(COALESCE(sum(a.filled_hc), 0), 4) AS filled_hc,
         count(DISTINCT a.employee_no)            AS actual_hc
  FROM public.employee_store_allocations a
  JOIN public.plantilla p ON p.id = a.plantilla_id
  WHERE a.is_active
    AND p.status = 'Active'
    AND (p.date_of_separation IS NULL OR p.date_of_separation > CURRENT_DATE)
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
  GROUP BY a.account_id
),
leave AS (
  SELECT p.account_id,
         count(*) AS leave_count
  FROM public.plantilla p
  WHERE p.status IN ('On Leave', 'on_leave')
    AND (p.date_of_separation IS NULL OR p.date_of_separation > CURRENT_DATE)
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
  GROUP BY p.account_id
),
active_pipeline_candidates AS (
  SELECT he.account_id,
         he.vcode,
         LOWER(TRIM(he.applicant_name)) AS cand_name,
         he.coverage_group_id,
         he.coverage_slot_id
  FROM public.hr_emploc he
  LEFT JOIN public.vacancies v ON v.id = he.vacancy_id
  WHERE he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
    AND he.deleted_at IS NULL
    AND COALESCE(v.is_pool_vacancy, false) = false
  UNION
  SELECT v.account_id,
         a.vacancy_vcode AS vcode,
         LOWER(TRIM(a.full_name)) AS cand_name,
         a.coverage_group_id,
         a.coverage_slot_id
  FROM public.applicants a
  JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
  WHERE a.status <> ALL (ARRAY['Backout'::text, 'Rejected'::text, 'Failed'::text, 'Did Not Report'::text, 'Rejected by Ops'::text, 'Withdrew'::text, 'Hired'::text, 'archived'::text])
    AND COALESCE(a.is_archived, false) = false
    AND COALESCE(v.is_pool_vacancy, false) = false
    AND NOT EXISTS (
      SELECT 1 FROM public.plantilla p_act
      WHERE p_act.account_id = v.account_id
        AND p_act.status IN ('Active', 'On Leave', 'on_leave')
        AND (p_act.date_of_separation IS NULL OR p_act.date_of_separation > CURRENT_DATE)
        AND COALESCE(p_act.is_deleted, false) = false
        AND COALESCE(p_act.is_archived, false) = false
        AND (
          (a.coverage_group_id IS NOT NULL AND p_act.coverage_group_id = a.coverage_group_id)
          OR LOWER(TRIM(p_act.employee_name)) = LOWER(TRIM(a.full_name))
        )
    )
),
pipeline AS (
  SELECT account_id,
         count(DISTINCT COALESCE(coverage_slot_id::text, coverage_group_id::text, cand_name)) AS pipeline_count
  FROM active_pipeline_candidates
  GROUP BY account_id
),
active_cg_with_pipeline AS (
  SELECT DISTINCT cgs.coverage_group_id
  FROM public.coverage_group_stores cgs
  JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
  JOIN public.stores s ON s.id = cgs.store_id
  WHERE cgs.archived_at IS NULL
    AND cg.archived_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.coverage_slots cs_act
      WHERE cs_act.coverage_group_id = cg.id
        AND cs_act.slot_status = 'active'
        AND cs_act.current_occupant_plantilla_id IS NOT NULL
    )
    AND (
      cg.id IN (SELECT coverage_group_id FROM active_pipeline_candidates WHERE coverage_group_id IS NOT NULL)
      OR s.vcode IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
      OR cgs.store_id IN (
        SELECT v.store_id FROM public.vacancies v
        WHERE v.vcode IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
      )
    )
),
coverage_slot_kpi AS (
  SELECT
    cg.account_id,
    COUNT(*) FILTER (
      WHERE cs.slot_status = 'active'
        AND (
          cs.current_occupant_plantilla_id IS NULL
          OR NOT EXISTS (
            SELECT 1 FROM public.employee_store_allocations esa
            WHERE esa.plantilla_id = cs.current_occupant_plantilla_id
              AND esa.account_id = cg.account_id
              AND esa.is_active = true
          )
        )
    )::numeric AS filled_hc,
    COUNT(DISTINCT cs.current_occupant_plantilla_id) FILTER (
      WHERE cs.slot_status = 'active'
        AND cs.current_occupant_plantilla_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM public.employee_store_allocations esa
          WHERE esa.plantilla_id = cs.current_occupant_plantilla_id
            AND esa.account_id = cg.account_id
            AND esa.is_active = true
        )
    ) AS actual_hc,
    COUNT(*) FILTER (
      WHERE cs.slot_status IN ('pipeline', 'hr_processing')
        AND cg.id NOT IN (SELECT coverage_group_id FROM active_cg_with_pipeline)
    ) AS pipeline_count,
    COUNT(*) FILTER (
      WHERE cs.slot_status = 'open'
        AND cg.id NOT IN (SELECT coverage_group_id FROM active_cg_with_pipeline)
    )::numeric AS slot_vacant_hc
  FROM public.coverage_slots cs
  JOIN public.coverage_groups cg ON cg.id = cs.coverage_group_id
  LEFT JOIN public.plantilla cp ON cp.id = cs.current_occupant_plantilla_id
  WHERE cg.archived_at IS NULL
    AND (
      cp.id IS NULL 
      OR (
        cp.status = 'Active' 
        AND (cp.date_of_separation IS NULL OR cp.date_of_separation > CURRENT_DATE)
        AND COALESCE(cp.is_deleted, false) = false
        AND COALESCE(cp.is_archived, false) = false
      )
    )
  GROUP BY cg.account_id
),
slot_vacant_non_roving AS (
  SELECT
    ps.account_id,
    COUNT(*) FILTER (
      WHERE ps.slot_status = 'open'
        AND ps.legacy_vcode NOT IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
    ) AS vacant_slots
  FROM public.plantilla_slots ps
  INNER JOIN public.vacancies v
    ON  v.vcode = ps.legacy_vcode
   AND  v.deleted_at IS NULL
   AND  COALESCE(v.is_archived, false)    = false
   AND  COALESCE(v.is_pool_vacancy, false) = false
  WHERE ps.is_roving    = false
    AND ps.legacy_vcode IS NOT NULL
    AND ps.account_id   IS NOT NULL
  GROUP BY ps.account_id
),
slot_vacant_roving AS (
  SELECT
    ps.account_id,
    SUM(
      CASE WHEN ps.slot_status = 'open'
            AND ps.legacy_vcode NOT IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
            AND NOT EXISTS (
              SELECT 1 FROM public.coverage_group_stores cgs
              WHERE cgs.store_id = ps.store_id
                AND cgs.coverage_group_id IN (SELECT coverage_group_id FROM active_cg_with_pipeline)
            )
           THEN 1.0 / NULLIF(grp.total_slots::numeric, 0)
           ELSE 0.0
      END
    ) AS vacant_hc
  FROM public.plantilla_slots ps
  JOIN (
    SELECT source_hc_request_id,
           COUNT(*) AS total_slots
    FROM public.plantilla_slots
    WHERE is_roving = true
      AND source_hc_request_id IS NOT NULL
    GROUP BY source_hc_request_id
  ) grp ON grp.source_hc_request_id = ps.source_hc_request_id
  WHERE ps.is_roving            = true
    AND ps.source_hc_request_id IS NOT NULL
    AND ps.account_id           IS NOT NULL
  GROUP BY ps.account_id
),
vacant AS (
  SELECT vv.account_id, count(*) AS open_hc
  FROM public.vacancies vv
  WHERE vv.status = 'Open'
    AND vv.deleted_at IS NULL
    AND COALESCE(vv.is_archived, false)       = false
    AND COALESCE(vv.is_pool_vacancy, false)   = false
    AND COALESCE(vv.affects_required_hc, true) = true
    AND vv.vcode NOT IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
    AND NOT EXISTS (
      SELECT 1 FROM public.coverage_group_stores cgs
      WHERE cgs.store_id = vv.store_id
        AND cgs.coverage_group_id IN (SELECT coverage_group_id FROM active_cg_with_pipeline)
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.plantilla_slots ps_chk
      WHERE ps_chk.legacy_vcode = vv.vcode
        AND ps_chk.closed_at IS NULL
        AND ps_chk.slot_status IN ('pipeline', 'hr_processing', 'occupied')
    )
  GROUP BY vv.account_id
),
base AS (
  SELECT
    a.id          AS account_id,
    a.account_name,
    a.account_code,
    a.group_id,
    g.group_name,
    g.group_code,
    round(
      COALESCE(f.filled_hc, 0)
    + COALESCE(csk.filled_hc, 0)
    + COALESCE(l.leave_count, 0),
    4)::numeric(12,4)                                                                AS filled_hc,
    (
      COALESCE(f.actual_hc, 0)
    + COALESCE(csk.actual_hc, 0)
    + COALESCE(l.leave_count, 0)
    )::bigint                                                                        AS actual_hc,
    (COALESCE(p.pipeline_count, 0) + COALESCE(csk.pipeline_count, 0))::bigint       AS pipeline_count,
    COALESCE(v.open_hc, 0)                                                           AS open_hc,
    round(
      COALESCE(svn.vacant_slots,   0)::numeric
    + COALESCE(svr.vacant_hc,      0)::numeric
    + COALESCE(csk.slot_vacant_hc, 0)::numeric,
    0)::numeric(12,4)                                                                AS slot_vacant_hc,
    round(
      COALESCE(f.filled_hc,          0)
    + COALESCE(csk.filled_hc,        0)
    + COALESCE(l.leave_count,        0)
    + COALESCE(p.pipeline_count,     0)
    + COALESCE(csk.pipeline_count,   0)
    + COALESCE(svn.vacant_slots,     0)::numeric
    + COALESCE(svr.vacant_hc,        0)::numeric
    + COALESCE(csk.slot_vacant_hc,   0)::numeric,
    0)::numeric(12,4)                                                                AS required_hc,
    COALESCE(l.leave_count, 0)::bigint                                               AS leave_count
  FROM public.accounts a
  LEFT JOIN public.groups          g    ON g.id          = a.group_id
  LEFT JOIN filled                 f    ON f.account_id  = a.id
  LEFT JOIN leave                  l    ON l.account_id  = a.id
  LEFT JOIN pipeline               p    ON p.account_id  = a.id
  LEFT JOIN coverage_slot_kpi      csk  ON csk.account_id = a.id
  LEFT JOIN vacant                 v    ON v.account_id  = a.id
  LEFT JOIN slot_vacant_non_roving svn  ON svn.account_id = a.id
  LEFT JOIN slot_vacant_roving     svr  ON svr.account_id = a.id
  WHERE a.is_active = true
    AND COALESCE(a.is_pool_account, false) = false
    AND (
         public.i_have_full_access()
      OR a.id = ANY (public.get_my_allowed_account_ids())
    )
)
SELECT
  account_id, account_name, account_code, group_id, group_name, group_code,
  filled_hc,
  actual_hc,
  pipeline_count,
  open_hc,
  required_hc,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(LEAST(1.0, GREATEST(0.0, actual_hc::numeric / required_hc)), 4) END AS mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(LEAST(1.0, GREATEST(0.0, (actual_hc::numeric + pipeline_count) / required_hc)), 4) END AS projected_mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(slot_vacant_hc / required_hc, 4) END                     AS vacancy_rate,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(pipeline_count / required_hc, 4) END                     AS pipeline_coverage,
  CASE WHEN required_hc = 0              THEN 'healthy'::text
       WHEN actual_hc::numeric / required_hc >= 1.0 THEN 'healthy'::text
       WHEN actual_hc::numeric / required_hc >= 0.9 THEN 'at_risk'::text
       ELSE                                   'critical'::text
  END                                                                       AS health_status,
  slot_vacant_hc,
  leave_count
FROM base;

ALTER VIEW public.v_account_allocation_kpi OWNER TO postgres;
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;


-- ────────────────────────────────────────────────────────────────────────────
-- 6. Backfill AGAWA, BERNARDINO OPENARIA in PERFECT SM (CG-PG3-0001)
--    - SMCO ONEMALL (VPSMG3_0008): Confirmed Onboard in HR Emploc ('For Emploc')
--    - SSM JAZZ (VPSMG3_0016): Remaining in Pipeline ('For Requirements')
-- ────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_cg_id          uuid := '40c09c8f-0d21-419b-b3ec-fcae5f5303b2'::uuid;
  v_cs_id          uuid := '50b5120e-3fdb-40b0-8019-0a1c06de750d'::uuid;
  v_app_onemall_id uuid := '017c34cb-8dc5-4134-ab41-20195236bfda'::uuid;
  v_hr_id          uuid := 'e6c7892b-18e6-4145-b063-1d7df5fc0afd'::uuid;
  v_store_onemall  uuid := '5fd29ec2-e3a7-45df-9f52-69b5ecd75525'::uuid;
  v_store_jazz     uuid := '26208810-9c64-4b2d-a49a-07fcf4cf89fc'::uuid;
  v_vac_onemall    uuid := 'a218c950-0e57-4da0-80c7-798ea60df6c4'::uuid;
  v_vac_jazz       uuid := '6d2914f8-7de4-49a3-a861-b80c2266ea47'::uuid;
BEGIN
  -- Only run backfill if Agawa's records exist on this environment (Staging)
  IF EXISTS (SELECT 1 FROM public.applicants WHERE id = v_app_onemall_id)
     AND EXISTS (SELECT 1 FROM public.coverage_groups WHERE id = v_cg_id)
  THEN
    -- 6a. Bind Agawa's SMCO ONEMALL applicant row to CG-PG3-0001
    UPDATE public.applicants
       SET slot_id           = NULL,
           coverage_group_id = v_cg_id,
           coverage_slot_id  = v_cs_id,
           updated_at        = NOW()
     WHERE id = v_app_onemall_id;

    -- 6b. Upgrade Agawa's hr_emploc row to Coverage Group mode (preserving hr_status = 'For Emploc' & docs)
    IF EXISTS (SELECT 1 FROM public.hr_emploc WHERE id = v_hr_id) THEN
      UPDATE public.hr_emploc
         SET assignment_type       = 'Coverage'::public.hr_emploc_assignment_type,
             vacancy_id            = NULL,
             roving_assignment_id  = NULL,
             slot_id               = NULL,
             coverage_group_id     = v_cg_id,
             coverage_slot_id      = v_cs_id,
             vcode                 = 'VPSMG3_0008',
             vacancy_code_snapshot = 'CG-PG3-0001',
             store_id              = v_store_onemall,
             store_name            = 'SMCO ONEMALL',
             covered_stores        = jsonb_build_array(
               jsonb_build_object(
                 'store_id',   v_store_onemall,
                 'store_name', 'SMCO ONEMALL',
                 'vcode',      'VPSMG3_0008',
                 'is_anchor',  true,
                 'status',     'Confirmed'
               ),
               jsonb_build_object(
                 'store_id',   v_store_jazz,
                 'store_name', 'SSM JAZZ',
                 'vcode',      'VPSMG3_0016',
                 'is_anchor',  false,
                 'status',     'Pending Requirements'
               )
             ),
             updated_at            = NOW()
       WHERE id = v_hr_id;

      -- 6c. Upsert hr_emploc_store_links (SMCO ONEMALL = Confirmed, SSM JAZZ = Pending)
      IF NOT EXISTS (
        SELECT 1 FROM public.hr_emploc_store_links
        WHERE hr_emploc_id = v_hr_id AND store_id = v_store_onemall AND deleted_at IS NULL
      ) THEN
        INSERT INTO public.hr_emploc_store_links (
          hr_emploc_id, coverage_group_id, coverage_slot_id, store_id,
          vacancy_id, vcode, store_name, account,
          status, confirmed_at
        ) VALUES (
          v_hr_id, v_cg_id, v_cs_id, v_store_onemall,
          v_vac_onemall, 'VPSMG3_0008', 'SMCO ONEMALL', 'PERFECT SM',
          'Confirmed', NOW()
        );
      END IF;

      IF NOT EXISTS (
        SELECT 1 FROM public.hr_emploc_store_links
        WHERE hr_emploc_id = v_hr_id AND store_id = v_store_jazz AND deleted_at IS NULL
      ) THEN
        INSERT INTO public.hr_emploc_store_links (
          hr_emploc_id, coverage_group_id, coverage_slot_id, store_id,
          vacancy_id, vcode, store_name, account,
          status, confirmed_at
        ) VALUES (
          v_hr_id, v_cg_id, v_cs_id, v_store_jazz,
          v_vac_jazz, 'VPSMG3_0016', 'SSM JAZZ', 'PERFECT SM',
          'Pending', NULL
        );
      END IF;
    END IF;

    -- 6d. Insert linked pipeline applicant row for SSM JAZZ (VPSMG3_0016) with status = 'For Requirements'
    IF NOT EXISTS (
      SELECT 1 FROM public.applicants
      WHERE vacancy_vcode = 'VPSMG3_0016'
        AND COALESCE(is_archived, false) = false
        AND LOWER(TRIM(full_name)) = 'agawa, bernardino openaria'
    ) THEN
      INSERT INTO public.applicants (
        vacancy_vcode,
        first_name, last_name, middle_name, full_name, full_name_snapshot,
        contact_number, status,
        coverage_group_id, coverage_slot_id,
        recruited_by_name, recruited_by_user_id,
        ops_remarks, is_archived
      ) VALUES (
        'VPSMG3_0016',
        'BERNARDINO', 'AGAWA', 'OPENARIA', 'AGAWA, BERNARDINO OPENARIA', 'AGAWA, BERNARDINO OPENARIA',
        '09987987987', 'For Requirements',
        v_cg_id, v_cs_id,
        'UAT Test 1', '908c1261-77cd-4963-a025-929b729dd39c'::uuid,
        'Remaining store for CG-PG3-0001 (Onboarded at SMCO ONEMALL)', false
      );
    END IF;

    -- 6e. Sync plantilla_slots and coverage_slots
    UPDATE public.plantilla_slots
       SET slot_status = 'hr_processing',
           updated_at  = NOW()
     WHERE legacy_vcode = 'VPSMG3_0008'
       AND closed_at IS NULL;

    UPDATE public.plantilla_slots
       SET slot_status = 'pipeline',
           updated_at  = NOW()
     WHERE legacy_vcode = 'VPSMG3_0016'
       AND closed_at IS NULL;

    UPDATE public.coverage_slots
       SET slot_status = 'hr_processing',
           updated_at  = NOW()
     WHERE id = v_cs_id;
  END IF;
END $$;

COMMIT;
