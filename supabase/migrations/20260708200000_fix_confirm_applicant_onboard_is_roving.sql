-- Migration: 20260708200000_fix_confirm_applicant_onboard_is_roving
-- Prompt ID: ohm#9f3a7c21
--
-- Purpose:
--   1. Fix compilation/runtime error "record v_vac has no field is_roving" inside
--      confirm_applicant_onboard (13-arg overload) by reverting the v_is_roving
--      calculation to check the applicant's roving assignment instead of the vacancies table.
--   2. Fix invalid columns "employee_name" and "full_name" in the INSERT INTO hr_emploc
--      statement, changing them to "applicant_name" and "applicant_name_snapshot" respectively.

BEGIN;

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
  p_hired_date               date    DEFAULT NULL::date,
  p_vacancy_requirement_id   uuid    DEFAULT NULL::uuid
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

  IF NOT FOUND THEN
    RAISE EXCEPTION 'vacancy % not found', v_app.vacancy_vcode
      USING ERRCODE = 'P0002';
  END IF;

  -- Revert to correct check: vacancies table does not contain is_roving column.
  v_is_roving := COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL;

  IF p_hired_by_user_id IS NOT NULL THEN
    v_hired_by_id := p_hired_by_user_id;
  ELSE
    v_hired_by_id := public.get_my_auth_uid();
  END IF;

  UPDATE public.applicants
     SET status             = 'Confirmed Onboard',
         last_name          = COALESCE(p_last_name,      last_name),
         first_name         = COALESCE(p_first_name,     first_name),
         middle_name        = COALESCE(p_middle_name,    middle_name),
         full_name          = COALESCE(p_full_name,      full_name),
         contact_number     = COALESCE(p_contact_number, contact_number),
         remarks            = COALESCE(p_remarks,        remarks),
         hired_date         = COALESCE(p_hired_date,     hired_date),
         hired_by           = v_hired_by_id::text,
         roving_assignment_id = COALESCE(
                                  p_roving_assignment_id,
                                  roving_assignment_id
                                ),
         last_activity_at   = NOW(),
         last_activity_by   = v_profile_id,
         updated_at         = NOW()
   WHERE id = p_applicant_id;

  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id;

  IF v_is_roving AND p_roving_assignment_id IS NULL THEN
    SELECT ra.id INTO v_roving_id
      FROM public.plantilla plt
      JOIN public.roving_assignments ra
        ON ra.plantilla_id = plt.id AND ra.is_active = true
     WHERE plt.employee_no = v_app.full_name
       AND plt.account = v_vac.account
     LIMIT 1;

    IF v_roving_id IS NULL THEN
      v_new_roving := true;
    END IF;
  ELSE
    v_roving_id := p_roving_assignment_id;
  END IF;

  SELECT plt.* INTO v_existing_plt
    FROM public.plantilla plt
   WHERE plt.account = v_vac.account
     AND (
       plt.employee_no ILIKE v_app.full_name
       OR plt.employee_name ILIKE v_app.full_name
     )
     AND plt.status IN ('Active', 'On Leave')
     AND NOT COALESCE(plt.is_deleted, false)
     AND NOT COALESCE(plt.is_archived, false)
   LIMIT 1;

  IF v_existing_plt.id IS NOT NULL THEN
    v_late_result := public.link_late_store_to_plantilla(
      p_plantilla_id      => v_existing_plt.id,
      p_vcode             => v_vac.vcode,
      p_vacancy_id        => v_vac.id,
      p_applicant_id      => v_app.id,
      p_performed_by      => v_profile_id
    );
  END IF;

  SELECT * INTO v_hr
    FROM public.hr_emploc
   WHERE applicant_id = p_applicant_id
   LIMIT 1;

  IF v_hr.id IS NOT NULL THEN
    UPDATE public.hr_emploc
       SET hr_status              = COALESCE(hr_status, 'Pending'),
           vacancy_requirement_id = COALESCE(vacancy_requirement_id, p_vacancy_requirement_id),
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
        p_vacancy_requirement_id
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
      'vacancy_requirement_id',     p_vacancy_requirement_id,
      'movement_at',                NOW()
    )
  );

  IF p_vacancy_requirement_id IS NOT NULL THEN
    UPDATE public.vacancy_requirements
       SET hc_filled = hc_filled + 1
     WHERE id = p_vacancy_requirement_id
       AND hc_filled < hc_needed;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'requirement_already_full'
        USING MESSAGE = 'The selected position requirement has no remaining headcount. '
                        'Another hire may have filled it concurrently.',
              HINT    = 'Refresh the vacancy and select a different requirement.';
    END IF;

  ELSE
    UPDATE public.vacancy_requirements
       SET hc_filled = hc_filled + 1
     WHERE id = (
       SELECT id
         FROM public.vacancy_requirements
        WHERE vacancy_id = v_vac.id
          AND hc_filled < hc_needed
        ORDER BY created_at
        LIMIT 1
     )
       AND hc_filled < hc_needed;
  END IF;

  IF NOT v_is_roving THEN
    PERFORM public.fn_sync_slot_to_hr_processing(
      p_vcode        => v_vac.vcode,
      p_applicant_id => v_app.id,
      p_performed_by => v_profile_id,
      p_source_fn    => 'confirm_applicant_onboard'
    );
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
    'vacancy_requirement_id',   p_vacancy_requirement_id
  );
END;
$function$;

ALTER FUNCTION public.confirm_applicant_onboard(uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date, uuid) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.confirm_applicant_onboard(uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_applicant_onboard(uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date, uuid) TO service_role;

COMMENT ON FUNCTION public.confirm_applicant_onboard(uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date, uuid) IS
  'ohm#9f3a7c21 — Fixes confirm_applicant_onboard is_roving syntax error by reverting v_is_roving calculation to COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL, and fixes invalid column names in hr_emploc INSERT.';

COMMIT;
