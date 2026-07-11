-- Migration: 20262406000004_fix_fn_update_applicant_pipeline_deployed_reliever_staging.sql
-- Scope: STAGING ONLY
-- Problem: fn_update_applicant_pipeline on staging referenced v_app.deployed_reliever and
--          v_app.deployed_commando as static columns in the main UPDATE SET clause.
--          Since applicants.deployed_reliever/deployed_commando do not exist on staging,
--          every call that resulted in any change threw:
--            PostgrestException: record "v_app" has no field "deployed_reliever" (42703)
-- Fix: Replace with the prod-authoritative version of fn_update_applicant_pipeline which:
--   1. Removes deployed_reliever/deployed_commando from the static UPDATE
--   2. Uses conditional EXECUTE (dynamic SQL) for those columns — schema-safe when absent
--   3. Uses applicant_status_history extended schema for ALL history (matches staging schema)
--   4. Updates last_activity_at/by/name in the main UPDATE (columns verified present on staging)
--   5. Does NOT reference applicant_pipeline_history (table absent on staging)
-- Safety: No DROP. No data mutation. Function replacement only (CREATE OR REPLACE).
-- Business rule preserved: deployed_reliever auto-stop on onboarding is handled by
--   confirm_applicant_onboard + its triggers — not this function. Unaffected.
--
-- Smoke tests (§S1–§S4):
-- §S1  Basic status update (no deployed_reliever param) succeeds without 42703
-- §S2  Follow-up date update succeeds and logs to applicant_status_history
-- §S3  Recruitment remarks update succeeds
-- §S4  Calling with p_deployed_reliever=true raises 42703 (column absent — correct guard)

CREATE OR REPLACE FUNCTION public.fn_update_applicant_pipeline(
  p_applicant_id uuid,
  p_new_status text DEFAULT NULL::text,
  p_follow_up_date date DEFAULT NULL::date,
  p_recruitment_remarks text DEFAULT NULL::text,
  p_ops_remarks text DEFAULT NULL::text,
  p_deployed_reliever boolean DEFAULT NULL::boolean,
  p_deployed_commando boolean DEFAULT NULL::boolean,
  p_reason_id uuid DEFAULT NULL::uuid,
  p_reason_type text DEFAULT NULL::text,
  p_clear_recruitment_remarks boolean DEFAULT false,
  p_clear_ops_remarks boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_level int := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_actor_name text;

  v_app record;
  v_vac record;
  v_old_status_code text;
  v_old_status_terminal boolean := false;
  v_new_status public.applicant_status_options%ROWTYPE;
  v_new_status_code text;
  v_new_status_label text;

  v_now timestamptz := now();
  v_history_ids uuid[] := ARRAY[]::uuid[];
  v_change_count int := 0;

  v_old_recruitment_remarks text;
  v_new_recruitment_remarks text;
  v_old_ops_remarks text;
  v_new_ops_remarks text;
  v_old_follow_up_date date;
  v_new_follow_up_date date;

  v_has_deployed_reliever boolean := false;
  v_has_deployed_commando boolean := false;
  v_old_deployed_reliever boolean;
  v_old_deployed_commando boolean;

  v_status_changed boolean := false;
  v_follow_up_changed boolean := false;
  v_recruitment_remarks_changed boolean := false;
  v_ops_remarks_changed boolean := false;
  v_deployed_reliever_changed boolean := false;
  v_deployed_commando_changed boolean := false;

  v_history_id uuid;
BEGIN
  IF v_level = 0 THEN
    RAISE EXCEPTION 'forbidden: authenticated user with a recognized role required'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason_type IS NOT NULL
     AND p_reason_type NOT IN ('backout', 'rejected', 'other') THEN
    RAISE EXCEPTION 'invalid reason_type: %. Must be backout | rejected | other', p_reason_type
      USING ERRCODE = '22023';
  END IF;

  IF p_new_status IS NULL
     AND p_follow_up_date IS NULL
     AND p_recruitment_remarks IS NULL
     AND p_ops_remarks IS NULL
     AND p_deployed_reliever IS NULL
     AND p_deployed_commando IS NULL
     AND NOT COALESCE(p_clear_recruitment_remarks, false)
     AND NOT COALESCE(p_clear_ops_remarks, false) THEN
    RAISE EXCEPTION 'no applicant pipeline changes requested'
      USING ERRCODE = '22023';
  END IF;

  PERFORM public.fn_assert_vacancy_edit_allowed_op('UPDATE');

  SELECT up.full_name
  INTO v_actor_name
  FROM public.users_profile up
  WHERE up.id = v_profile_id;

  SELECT *
  INTO v_app
  FROM public.applicants
  WHERE id = p_applicant_id
    AND COALESCE(is_archived, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  SELECT *
  INTO v_vac
  FROM public.vacancies
  WHERE vcode = v_app.vacancy_vcode;

  IF v_vac.source = 'pool' AND NOT (v_level = 100 OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'only HRCO/ATL/TL/OM or Super Admin may update pool vacancy applicants'
      USING ERRCODE = '42501';
  END IF;

  v_old_status_code := lower(regexp_replace(COALESCE(v_app.status, ''), '[^a-zA-Z0-9]+', '_', 'g'));

  SELECT is_terminal
  INTO v_old_status_terminal
  FROM public.applicant_status_options
  WHERE status_code = v_old_status_code
     OR label = v_app.status
     OR lower(regexp_replace(COALESCE(label, ''), '[^a-zA-Z0-9]+', '_', 'g')) = v_old_status_code
  ORDER BY CASE WHEN status_code = v_old_status_code THEN 0 ELSE 1 END
  LIMIT 1;

  IF COALESCE(v_old_status_terminal, false) AND v_level < 100 THEN
    RAISE EXCEPTION 'cannot change status from terminal status % without Super Admin override', v_app.status
      USING ERRCODE = '42501';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'applicants' AND column_name = 'deployed_reliever'
  ) INTO v_has_deployed_reliever;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'applicants' AND column_name = 'deployed_commando'
  ) INTO v_has_deployed_commando;

  IF p_deployed_reliever IS NOT NULL AND NOT v_has_deployed_reliever THEN
    RAISE EXCEPTION 'applicants.deployed_reliever is not available in this schema'
      USING ERRCODE = '42703';
  END IF;

  IF p_deployed_commando IS NOT NULL AND NOT v_has_deployed_commando THEN
    RAISE EXCEPTION 'applicants.deployed_commando is not available in this schema'
      USING ERRCODE = '42703';
  END IF;

  IF (p_deployed_reliever IS NOT NULL OR p_deployed_commando IS NOT NULL)
     AND NOT (v_level = 100 OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'only HRCO/ATL/TL/OM or Super Admin may update deployment flags'
      USING ERRCODE = '42501';
  END IF;

  IF p_new_status IS NOT NULL THEN
    v_new_status_code := lower(regexp_replace(btrim(p_new_status), '[^a-zA-Z0-9]+', '_', 'g'));

    SELECT *
    INTO v_new_status
    FROM public.applicant_status_options aso
    WHERE aso.is_active = true
      AND (
        aso.status_code = v_new_status_code
        OR aso.label = btrim(p_new_status)
        OR lower(regexp_replace(aso.label, '[^a-zA-Z0-9]+', '_', 'g')) = v_new_status_code
      )
    LIMIT 1;

    IF v_new_status.status_code IS NULL THEN
      RAISE EXCEPTION 'invalid status: %', p_new_status
        USING ERRCODE = '22023';
    END IF;

    IF v_new_status.status_code <> v_old_status_code THEN
      v_status_changed := true;
      v_new_status_label := v_new_status.label;
    END IF;
  END IF;

  IF p_follow_up_date IS NOT NULL AND COALESCE(v_app.follow_up_date, '1970-01-01'::date) <> p_follow_up_date THEN
    v_follow_up_changed := true;
    v_old_follow_up_date := v_app.follow_up_date;
    v_new_follow_up_date := p_follow_up_date;
  END IF;

  IF COALESCE(p_clear_recruitment_remarks, false) THEN
    IF v_app.recruitment_remarks IS NOT NULL THEN
      v_recruitment_remarks_changed := true;
      v_old_recruitment_remarks := v_app.recruitment_remarks;
      v_new_recruitment_remarks := NULL;
    END IF;
  ELSIF p_recruitment_remarks IS NOT NULL AND COALESCE(v_app.recruitment_remarks, '') <> btrim(p_recruitment_remarks) THEN
    v_recruitment_remarks_changed := true;
    v_old_recruitment_remarks := v_app.recruitment_remarks;
    v_new_recruitment_remarks := btrim(p_recruitment_remarks);
  END IF;

  IF COALESCE(p_clear_ops_remarks, false) THEN
    IF v_app.ops_remarks IS NOT NULL THEN
      v_ops_remarks_changed := true;
      v_old_ops_remarks := v_app.ops_remarks;
      v_new_ops_remarks := NULL;
    END IF;
  ELSIF p_ops_remarks IS NOT NULL AND COALESCE(v_app.ops_remarks, '') <> btrim(p_ops_remarks) THEN
    v_ops_remarks_changed := true;
    v_old_ops_remarks := v_app.ops_remarks;
    v_new_ops_remarks := btrim(p_ops_remarks);
  END IF;

  IF v_has_deployed_reliever AND p_deployed_reliever IS NOT NULL THEN
    EXECUTE 'SELECT COALESCE(deployed_reliever, false) FROM public.applicants WHERE id = $1'
      INTO v_old_deployed_reliever USING v_app.id;
    IF v_old_deployed_reliever <> p_deployed_reliever THEN
      v_deployed_reliever_changed := true;
    END IF;
  END IF;

  IF v_has_deployed_commando AND p_deployed_commando IS NOT NULL THEN
    EXECUTE 'SELECT COALESCE(deployed_commando, false) FROM public.applicants WHERE id = $1'
      INTO v_old_deployed_commando USING v_app.id;
    IF v_old_deployed_commando <> p_deployed_commando THEN
      v_deployed_commando_changed := true;
    END IF;
  END IF;

  IF NOT (
    v_status_changed OR
    v_follow_up_changed OR
    v_recruitment_remarks_changed OR
    v_ops_remarks_changed OR
    v_deployed_reliever_changed OR
    v_deployed_commando_changed
  ) THEN
    RETURN jsonb_build_object('ok', true, 'applicant_id', v_app.id, 'changed', false);
  END IF;

  -- deployed_reliever/deployed_commando are NOT set here — they go through
  -- EXECUTE below so the UPDATE is safe when those columns do not exist.
  UPDATE public.applicants
  SET
    status            = CASE WHEN v_status_changed             THEN v_new_status_label      ELSE status            END,
    follow_up_date    = CASE WHEN v_follow_up_changed          THEN v_new_follow_up_date     ELSE follow_up_date    END,
    recruitment_remarks = CASE WHEN v_recruitment_remarks_changed THEN v_new_recruitment_remarks ELSE recruitment_remarks END,
    ops_remarks       = CASE WHEN v_ops_remarks_changed        THEN v_new_ops_remarks        ELSE ops_remarks       END,
    last_activity_at  = v_now,
    last_activity_by  = v_profile_id,
    last_activity_by_name = v_actor_name,
    updated_at        = v_now,
    updated_by        = v_profile_id
  WHERE id = v_app.id;

  IF v_deployed_reliever_changed THEN
    EXECUTE 'UPDATE public.applicants SET deployed_reliever = $1 WHERE id = $2'
      USING p_deployed_reliever, v_app.id;
  END IF;

  IF v_deployed_commando_changed THEN
    EXECUTE 'UPDATE public.applicants SET deployed_commando = $1 WHERE id = $2'
      USING p_deployed_commando, v_app.id;
  END IF;

  IF v_status_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, changed_by_name
    ) VALUES (
      v_history_id, v_app.id, v_app.status, v_new_status_label,
      p_reason_id, p_reason_type, NULL, v_profile_id, v_now, 'vacancy',
      'status_change', 'status', v_app.status, v_new_status_label, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_follow_up_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_follow_up_date, new_follow_up_date,
      changed_by_name
    ) VALUES (
      v_history_id, v_app.id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'follow_up_update',
      'follow_up_date', v_old_follow_up_date::text, v_new_follow_up_date::text,
      v_old_follow_up_date, v_new_follow_up_date, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_recruitment_remarks_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_recruitment_remarks,
      new_recruitment_remarks, changed_by_name
    ) VALUES (
      v_history_id, v_app.id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'recruitment_remarks_update',
      'recruitment_remarks', v_old_recruitment_remarks, v_new_recruitment_remarks,
      v_old_recruitment_remarks, v_new_recruitment_remarks, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_ops_remarks_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_ops_remarks, new_ops_remarks,
      changed_by_name
    ) VALUES (
      v_history_id, v_app.id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'ops_remarks_update',
      'ops_remarks', v_old_ops_remarks, v_new_ops_remarks,
      v_old_ops_remarks, v_new_ops_remarks, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_deployed_reliever_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_deployed_reliever,
      new_deployed_reliever, changed_by_name
    ) VALUES (
      v_history_id, v_app.id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'deployed_reliever_update',
      'deployed_reliever', v_old_deployed_reliever::text, p_deployed_reliever::text,
      v_old_deployed_reliever, p_deployed_reliever, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_deployed_commando_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_deployed_commando,
      new_deployed_commando, changed_by_name
    ) VALUES (
      v_history_id, v_app.id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'deployed_commando_update',
      'deployed_commando', v_old_deployed_commando::text, p_deployed_commando::text,
      v_old_deployed_commando, p_deployed_commando, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_status_changed THEN
    DECLARE
      v_slot_type text := 'stationary';
    BEGIN
      IF v_app.coverage_slot_id IS NOT NULL THEN
        v_slot_type := 'roving';
      END IF;

      IF v_slot_type = 'roving' THEN
        IF v_new_status.is_terminal THEN
          PERFORM public.fn_release_coverage_slot(v_app.coverage_slot_id, v_profile_id);
        END IF;
      ELSE
        PERFORM public.fn_sync_vacancy_slot_open_pipeline(
          v_app.vacancy_vcode,
          v_profile_id,
          p_source_fn => 'fn_update_applicant_pipeline'
        );
      END IF;
    END;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'applicant_id', v_app.id,
    'changed', true,
    'change_count', v_change_count,
    'history_ids', v_history_ids
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_update_applicant_pipeline(
  uuid, text, date, text, text, boolean, boolean, uuid, text, boolean, boolean
) TO authenticated;
