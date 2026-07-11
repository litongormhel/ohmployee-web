-- ============================================================
-- OHM2026_0087A_FIX1 — Coverage Group HR Emploc assignment type
-- Migration: 20261003000001_fix_coverage_group_emploc_assignment_type.sql
-- ============================================================
-- Fixes confirm_coverage_group_onboarding failing
-- hr_emploc_assignment_type_consistency_chk by writing Coverage rows with the
-- slot-first Coverage field combination instead of legacy Roving.

-- §1. HR Emploc assignment contract
ALTER TABLE public.hr_emploc
  DROP CONSTRAINT IF EXISTS hr_emploc_assignment_type_consistency_chk;

ALTER TABLE public.hr_emploc
  ADD CONSTRAINT hr_emploc_assignment_type_consistency_chk
  CHECK (
       (
         assignment_type = 'Stationary'::public.hr_emploc_assignment_type
         AND roving_assignment_id IS NULL
         AND vacancy_id IS NOT NULL
         AND coverage_slot_id IS NULL
         AND coverage_group_id IS NULL
       )
    OR (
         assignment_type = 'Roving'::public.hr_emploc_assignment_type
         AND roving_assignment_id IS NOT NULL
         AND coverage_slot_id IS NULL
         AND coverage_group_id IS NULL
       )
    OR (
         assignment_type = 'Coverage'::public.hr_emploc_assignment_type
         AND roving_assignment_id IS NULL
         AND vacancy_id IS NULL
         AND coverage_slot_id IS NOT NULL
         AND coverage_group_id IS NOT NULL
       )
  ) NOT VALID;

COMMENT ON CONSTRAINT hr_emploc_assignment_type_consistency_chk ON public.hr_emploc IS
  'OHM2026_0087A_FIX1: Stationary uses vacancy_id only; legacy Roving uses '
  'roving_assignment_id only; Coverage Group onboarding uses coverage_slot_id '
  '+ coverage_group_id and no legacy roving_assignment_id/vacancy_id.';

COMMENT ON COLUMN public.hr_emploc.assignment_type IS
  'Stationary = single applicant pinned to a vacancy. Roving = legacy roving_assignments group. Coverage = Coverage Group slot-first onboarding via coverage_slot_id + coverage_group_id.';

-- §2. Store-link binding contract
-- Coverage Group store links bind through coverage_group_id, not the legacy
-- roving_assignment_id. Keep legacy roving writes valid while allowing CG links.
ALTER TABLE public.hr_emploc_store_links
  ALTER COLUMN roving_assignment_id DROP NOT NULL;

ALTER TABLE public.hr_emploc_store_links
  DROP CONSTRAINT IF EXISTS hr_emploc_store_links_binding_chk;

ALTER TABLE public.hr_emploc_store_links
  ADD CONSTRAINT hr_emploc_store_links_binding_chk
  CHECK (roving_assignment_id IS NOT NULL OR coverage_group_id IS NOT NULL) NOT VALID;

COMMENT ON CONSTRAINT hr_emploc_store_links_binding_chk ON public.hr_emploc_store_links IS
  'OHM2026_0087A_FIX1: legacy roving links use roving_assignment_id; Coverage Group links use coverage_group_id.';

-- §3. Replace confirm_coverage_group_onboarding RPC
CREATE OR REPLACE FUNCTION public.confirm_coverage_group_onboarding(
  p_applicant_id             uuid,
  p_selected_store_ids       uuid[],
  p_hired_by_user_id         uuid    DEFAULT NULL,
  p_hired_date               date    DEFAULT NULL,
  p_remarks                  text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
     SET status = 'Confirmed Onboard',
         hired_date = COALESCE(p_hired_date, hired_date, CURRENT_DATE),
         hired_at = COALESCE(hired_at, NOW()),
         hired_by = v_actor_name,
         hired_by_team = v_role,
         hired_by_user_id = v_hired_by_id,
         deployed_by_user_id = v_profile_id,
         updated_at = NOW(),
         updated_by = v_profile_id
   WHERE id = p_applicant_id;

  -- 7. Insert single Coverage HR Emploc record
  INSERT INTO public.hr_emploc (
    applicant_name, applicant_name_snapshot, applicant_id,
    vcode, vacancy_code_snapshot,
    account, account_id, position_id_snapshot, position,
    status, hr_status, hired_date,
    deployed_by_user_id, created_by, updated_by, date_requested,
    assignment_type, coverage_group_id, coverage_slot_id, covered_stores,
    ops_remarks
  ) VALUES (
    v_app.full_name, v_app.full_name, v_app.id,
    v_group.coverage_code, v_group.coverage_code,
    (SELECT account_name FROM public.accounts WHERE id = v_group.account_id),
    v_group.account_id, v_group.position_id,
    (SELECT position_name FROM public.positions WHERE id = v_group.position_id),
    'Pending Emploc', 'Pending', COALESCE(p_hired_date, CURRENT_DATE),
    v_profile_id, v_profile_id, v_profile_id, NOW(),
    'Coverage'::public.hr_emploc_assignment_type,
    v_group.id, v_app.coverage_slot_id, v_covered_json,
    p_remarks
  )
  RETURNING * INTO v_hr;

  -- 8. Populate hr_emploc_store_links for each selected store
  FOR v_store_id IN SELECT DISTINCT unnest(p_selected_store_ids) LOOP
    SELECT s.store_name, cgs.is_anchor INTO v_store_record
      FROM public.coverage_group_stores cgs
      JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.coverage_group_id = v_group.id
       AND cgs.store_id = v_store_id
       AND cgs.archived_at IS NULL;

    INSERT INTO public.hr_emploc_store_links (
      hr_emploc_id, coverage_group_id, store_id, vcode, store_name, account,
      status, confirmed_at, confirmed_by, created_by, updated_by
    ) VALUES (
      v_hr.id, v_group.id, v_store_id, v_group.coverage_code,
      v_store_record.store_name, v_hr.account,
      'Confirmed', NOW(), v_profile_id, v_profile_id, v_profile_id
    );
  END LOOP;

  -- 9. Transition Slot status from 'pipeline' to 'hr_processing'
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
$$;

COMMENT ON FUNCTION public.confirm_coverage_group_onboarding(uuid, uuid[], uuid, date, text) IS
  'OHM2026_0087A_FIX1: Confirms a Coverage Group applicant for onboarding. Creates one Coverage HR Emploc row with coverage_slot_id + coverage_group_id, selected store links, and exact slot pipeline->hr_processing.';

REVOKE ALL ON FUNCTION public.confirm_coverage_group_onboarding(uuid, uuid[], uuid, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_coverage_group_onboarding(uuid, uuid[], uuid, date, text) TO authenticated;
