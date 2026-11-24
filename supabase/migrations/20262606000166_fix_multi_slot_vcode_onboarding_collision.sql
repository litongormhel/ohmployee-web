-- ============================================================
-- Migration: 20262606000166_fix_multi_slot_vcode_onboarding_collision.sql
-- Description: Fix multi-slot VCode onboarding collision on uq_hr_emploc_one_active_per_slot.
-- Hardens fn_sync_slot_to_hr_processing and confirm_applicant_onboard:
--   1. fn_sync_slot_to_hr_processing:
--      - Accepts and honors p_slot_id.
--      - Falls back to applicant's bound slot_id if p_slot_id is NULL.
--      - If still NULL, selects an available, unowned slot (slot_status IN ('pipeline', 'open'),
--        excluding any slots currently owned by an active hr_emploc row), ordered by pipeline first,
--        then slot_ordinal ASC.
--      - Ensures slot_id is always returned in the jsonb result.
--   2. confirm_applicant_onboard:
--      - Passes v_app.slot_id as p_slot_id into fn_sync_slot_to_hr_processing.
--      - Synchronizes the resolved slot_id back to applicants.slot_id and hr_emploc.slot_id.
--   3. Data Alignment:
--      - Backfills applicants.slot_id from hr_emploc.slot_id for active onboarded candidates.
--      - Binds candidate Jimmy Delos Santos (VCAG5_0056) to available pipeline Slot Ordinal 2.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. Hardened fn_sync_slot_to_hr_processing
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sync_slot_to_hr_processing(
  p_vcode text,
  p_applicant_id uuid DEFAULT NULL::uuid,
  p_performed_by uuid DEFAULT NULL::uuid,
  p_source_fn text DEFAULT NULL::text,
  p_slot_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
/*
  Phase C upgrade — non-blocking pipeline→hr_processing slot sync (OHM2026_0045).
  Multi-slot hardened: resolves unowned available slots when p_slot_id is not provided,
  preventing duplicate key collisions on uq_hr_emploc_one_active_per_slot.
*/
DECLARE
  v_slot_id uuid;
  v_result  jsonb;
BEGIN

  -- ── 1. Explicit slot_id provided ──────────────────────────────────────────
  IF p_slot_id IS NOT NULL THEN
    v_slot_id := p_slot_id;
  END IF;

  -- ── 2. Fall back to applicant's already-bound slot_id ─────────────────────
  IF v_slot_id IS NULL AND p_applicant_id IS NOT NULL THEN
    SELECT slot_id INTO v_slot_id
    FROM   public.applicants
    WHERE  id = p_applicant_id
      AND  slot_id IS NOT NULL;
  END IF;

  -- ── 3. Fall back to locating an available unowned slot for this VCode ──────
  IF v_slot_id IS NULL THEN
    IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
      RAISE NOTICE
        'fn_sync_slot_to_hr_processing: skipped — p_vcode null/empty and p_slot_id null (source=%)',
        COALESCE(p_source_fn, 'unknown');
      RETURN NULL;
    END IF;

    -- Prioritize slots in 'pipeline' (already reserved for candidate), then 'open' slots.
    -- Crucially: exclude any slot that already belongs to an active (non-deleted) hr_emploc row.
    SELECT ps.id INTO v_slot_id
    FROM   public.plantilla_slots ps
    WHERE  ps.legacy_vcode = p_vcode
      AND  ps.is_roving    = false
      AND  ps.slot_status IN ('pipeline', 'open')
      AND  ps.closed_at IS NULL
      AND  ps.current_occupant_plantilla_id IS NULL
      AND  NOT EXISTS (
        SELECT 1 FROM public.hr_emploc he
        WHERE  he.slot_id = ps.id
          AND  he.deleted_at IS NULL
      )
    ORDER  BY
      CASE WHEN ps.slot_status = 'pipeline' THEN 0 ELSE 1 END,
      ps.slot_ordinal ASC, ps.created_at ASC, ps.id ASC
    LIMIT  1;
  END IF;

  -- ── 4. Edge-case fallback for pre-slot legacy vacancies ────────────────────
  IF v_slot_id IS NULL THEN
    SELECT ps.id INTO v_slot_id
    FROM   public.plantilla_slots ps
    WHERE  ps.legacy_vcode = p_vcode
      AND  ps.is_roving    = false
      AND  NOT EXISTS (
        SELECT 1 FROM public.hr_emploc he
        WHERE  he.slot_id = ps.id
          AND  he.deleted_at IS NULL
      )
    ORDER  BY ps.slot_ordinal ASC
    LIMIT  1;

    IF v_slot_id IS NULL THEN
      -- No available unowned slot for this VCODE
      RETURN NULL;
    END IF;
  END IF;

  -- ── 5. Transition slot to hr_processing ───────────────────────────────────
  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => 'hr_processing',
    p_reason_code           => 'REPLACEMENT',
    p_performed_by          => p_performed_by,
    p_remarks               => format(
      'Phase C / %s / VCODE=%s / applicant_id=%s / slot_id=%s',
      COALESCE(p_source_fn,    'unknown'),
      COALESCE(p_vcode,        'unknown'),
      COALESCE(p_applicant_id::text, 'null'),
      v_slot_id
    ),
    p_occupant_plantilla_id => NULL
  ) INTO v_result;

  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_slot_to_hr_processing: % for slot_id=% VCODE=% source=% — %',
      v_result->>'status',
      v_slot_id,
      COALESCE(p_vcode, 'unknown'),
      COALESCE(p_source_fn, 'unknown'),
      COALESCE(v_result->>'blocked_reason', 'same-state no_op');
  END IF;

  -- Ensure result always exposes the resolved slot_id
  IF v_result IS NOT NULL THEN
    v_result := v_result || jsonb_build_object('slot_id', v_slot_id);
  ELSE
    v_result := jsonb_build_object('status', 'ok', 'slot_id', v_slot_id);
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  -- Non-blocking contract: log and skip. Host RPC transaction continues.
  RAISE NOTICE
    'fn_sync_slot_to_hr_processing: error for VCODE=% slot_id=% source=% — % (sqlstate=%)',
    COALESCE(p_vcode, 'null'),
    COALESCE(p_slot_id::text, 'null'),
    COALESCE(p_source_fn, 'unknown'),
    SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$function$;

COMMENT ON FUNCTION public.fn_sync_slot_to_hr_processing(text, uuid, uuid, text, uuid) IS
  'Phase C / Multi-Slot hardened: syncs an available unowned plantilla_slot to hr_processing, honoring p_slot_id or applicant slot_id, and excluding slots already assigned in hr_emploc.';

GRANT EXECUTE ON FUNCTION public.fn_sync_slot_to_hr_processing(text, uuid, uuid, text, uuid) TO authenticated, service_role;


-- ────────────────────────────────────────────────────────────
-- 2. Hardened confirm_applicant_onboard (13-param version)
-- ────────────────────────────────────────────────────────────
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
    -- Capture the return value and explicitly pass v_app.slot_id
    v_slot_sync_result := public.fn_sync_slot_to_hr_processing(
      p_vcode        => v_vac.vcode,
      p_applicant_id => v_app.id,
      p_performed_by => v_profile_id,
      p_source_fn    => 'confirm_applicant_onboard',
      p_slot_id      => v_app.slot_id
    );

    IF v_hr.id IS NOT NULL AND (v_slot_sync_result->>'slot_id') IS NOT NULL THEN
      UPDATE public.hr_emploc
         SET slot_id = (v_slot_sync_result->>'slot_id')::uuid
       WHERE id = v_hr.id
         AND slot_id IS NULL;

      UPDATE public.applicants
         SET slot_id = (v_slot_sync_result->>'slot_id')::uuid
       WHERE id = v_app.id
         AND slot_id IS NULL;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok',                       true,
    'applicant_id',             v_app.id,
    'applicant_status',         v_app.status,
    'hr_emploc_id',             v_hr.id,
    'vcode',                    v_vac.vcode,
    'hired_by_user_id',         v_hired_by_id,
    'hired_date',                v_app.hired_date,
    'is_roving',                v_is_roving,
    'late_store_linked',        v_late_result,
    'vacancy_requirement_id',   v_resolved_requirement_id
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.confirm_applicant_onboard(
  uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date, uuid
) TO authenticated, service_role;


-- ────────────────────────────────────────────────────────────
-- 3. Data Alignment & Backfill
-- ────────────────────────────────────────────────────────────
-- 3a. Backfill applicants.slot_id from hr_emploc.slot_id for active onboarded candidates
UPDATE public.applicants a
SET slot_id = he.slot_id
FROM public.hr_emploc he
WHERE he.applicant_id = a.id
  AND a.slot_id IS NULL
  AND he.slot_id IS NOT NULL
  AND he.deleted_at IS NULL;

-- 3b. Bind Jimmy Delos Santos (VCAG5_0056) to available pipeline Slot Ordinal 2
UPDATE public.applicants
SET slot_id = '79e510b4-0b6f-40ec-8e16-4f16d504ab82'::uuid
WHERE id = 'b8f5c945-5d8c-4c05-b5b3-eccd13776016'::uuid
  AND vacancy_vcode = 'VCAG5_0056'
  AND slot_id IS NULL;
