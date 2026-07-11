-- ============================================================
-- OHMployee - Applicant Pipeline SEAM 2 Backend
-- Prompt ID : OHM2026_0095B
-- Date      : 2026-06-01
-- Scope     : Add applicant pipeline fields, extend history, and create
--             fn_update_applicant_pipeline.
--
-- Explicitly out of scope:
--   - Flutter changes
--   - Supabase apply/db push
--   - CGCODE architecture changes
--   - Slot changes / slot sync hooks
--   - Plantilla lifecycle changes
--   - SEAM 1 status seed/status predicate changes
-- ============================================================

-- ============================================================
-- 1. Extend applicants
-- ============================================================

ALTER TABLE public.applicants
  ADD COLUMN IF NOT EXISTS follow_up_date date,
  ADD COLUMN IF NOT EXISTS recruitment_remarks text,
  ADD COLUMN IF NOT EXISTS ops_remarks text,
  ADD COLUMN IF NOT EXISTS last_activity_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_activity_by uuid REFERENCES public.users_profile(id),
  ADD COLUMN IF NOT EXISTS last_activity_by_name text;

-- Disable the edit-lock trigger for schema-bootstrap backfills only.
-- The trigger blocks non-SA/HA UPDATEs during the scheduled lock window;
-- the migration runner has no auth context. Re-enabled immediately after.
-- Precedent: 20260629 and 20260630 use the same pattern for public.vacancies.
ALTER TABLE public.applicants DISABLE TRIGGER trg_assert_applicant_edit_allowed;

UPDATE public.applicants
SET recruitment_remarks = remarks
WHERE recruitment_remarks IS NULL
  AND remarks IS NOT NULL
  AND btrim(remarks) <> '';

UPDATE public.applicants
SET follow_up_date = CURRENT_DATE
WHERE follow_up_date IS NULL;

UPDATE public.applicants
SET last_activity_at = COALESCE(updated_at, created_at, now())
WHERE last_activity_at IS NULL;

ALTER TABLE public.applicants ENABLE TRIGGER trg_assert_applicant_edit_allowed;

ALTER TABLE public.applicants
  ALTER COLUMN follow_up_date SET DEFAULT CURRENT_DATE,
  ALTER COLUMN follow_up_date SET NOT NULL;

COMMENT ON COLUMN public.applicants.follow_up_date IS
  'Required applicant pipeline follow-up date. Defaults to CURRENT_DATE.';
COMMENT ON COLUMN public.applicants.recruitment_remarks IS
  'Recruitment-owned applicant pipeline remarks. Editable by Recruitment and Super Admin.';
COMMENT ON COLUMN public.applicants.ops_remarks IS
  'Operations-owned applicant pipeline remarks. Editable by HRCO/ATL/TL/OM and Super Admin.';
COMMENT ON COLUMN public.applicants.last_activity_at IS
  'UTC timestamptz for the last applicant pipeline change.';
COMMENT ON COLUMN public.applicants.last_activity_by IS
  'users_profile.id snapshot for the last applicant pipeline change.';
COMMENT ON COLUMN public.applicants.last_activity_by_name IS
  'Display-name snapshot for the last applicant pipeline change.';

-- ============================================================
-- 2. Extend applicant_status_history
-- ============================================================

ALTER TABLE public.applicant_status_history
  ALTER COLUMN to_status DROP NOT NULL;

ALTER TABLE public.applicant_status_history
  ADD COLUMN IF NOT EXISTS update_type text NOT NULL DEFAULT 'status_change',
  ADD COLUMN IF NOT EXISTS changed_field text,
  ADD COLUMN IF NOT EXISTS old_value text,
  ADD COLUMN IF NOT EXISTS new_value text,
  ADD COLUMN IF NOT EXISTS old_recruitment_remarks text,
  ADD COLUMN IF NOT EXISTS new_recruitment_remarks text,
  ADD COLUMN IF NOT EXISTS old_ops_remarks text,
  ADD COLUMN IF NOT EXISTS new_ops_remarks text,
  ADD COLUMN IF NOT EXISTS old_follow_up_date date,
  ADD COLUMN IF NOT EXISTS new_follow_up_date date,
  ADD COLUMN IF NOT EXISTS old_deployed_reliever boolean,
  ADD COLUMN IF NOT EXISTS new_deployed_reliever boolean,
  ADD COLUMN IF NOT EXISTS old_deployed_commando boolean,
  ADD COLUMN IF NOT EXISTS new_deployed_commando boolean,
  ADD COLUMN IF NOT EXISTS changed_by_name text;

ALTER TABLE public.applicant_status_history
  DROP CONSTRAINT IF EXISTS chk_ash_update_type;

ALTER TABLE public.applicant_status_history
  ADD CONSTRAINT chk_ash_update_type
  CHECK (update_type IN (
    'status_change',
    'follow_up_update',
    'recruitment_remarks_update',
    'ops_remarks_update',
    'deployed_reliever_update',
    'deployed_commando_update'
  ));

CREATE INDEX IF NOT EXISTS idx_applicant_status_history_changed_field
  ON public.applicant_status_history (applicant_id, changed_field, changed_at DESC);

COMMENT ON COLUMN public.applicant_status_history.changed_field IS
  'Field changed by fn_update_applicant_pipeline; one history row is written per changed field.';
COMMENT ON COLUMN public.applicant_status_history.old_value IS
  'Generic text snapshot of the old field value for display/audit.';
COMMENT ON COLUMN public.applicant_status_history.new_value IS
  'Generic text snapshot of the new field value for display/audit.';
COMMENT ON COLUMN public.applicant_status_history.changed_by_name IS
  'Display-name snapshot of the actor at change time.';

-- ============================================================
-- 3. fn_update_applicant_pipeline
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_update_applicant_pipeline(
  p_applicant_id uuid,
  p_new_status text DEFAULT NULL,
  p_follow_up_date date DEFAULT NULL,
  p_recruitment_remarks text DEFAULT NULL,
  p_ops_remarks text DEFAULT NULL,
  p_deployed_reliever boolean DEFAULT NULL,
  p_deployed_commando boolean DEFAULT NULL,
  p_reason_id uuid DEFAULT NULL,
  p_reason_type text DEFAULT NULL,
  p_clear_recruitment_remarks boolean DEFAULT false,
  p_clear_ops_remarks boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level int := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_actor_name text;

  v_app record;
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

  -- Vacancy module lock is authoritative for applicant pipeline updates.
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

  -- HA has full read visibility elsewhere but is explicitly read-only here.
  IF v_level = 90 THEN
    RAISE EXCEPTION 'Head Admin is read-only for applicant pipeline updates'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (v_level = 100 OR public.i_am_recruitment() OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'forbidden: applicant pipeline updates are limited to Recruitment, HRCO/ATL/TL/OM, and Super Admin'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.vacancies v
      WHERE v.vcode = v_app.vacancy_vcode
        AND v.account = ANY(public.get_my_allowed_accounts())
        AND v.deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT aso.status_code, aso.is_terminal
  INTO v_old_status_code, v_old_status_terminal
  FROM public.applicant_status_options aso
  WHERE aso.status_code = v_app.status
     OR aso.label = v_app.status
     OR lower(regexp_replace(aso.label, '[^a-zA-Z0-9]+', '_', 'g')) =
        lower(regexp_replace(COALESCE(v_app.status, ''), '[^a-zA-Z0-9]+', '_', 'g'))
  ORDER BY CASE WHEN aso.status_code = v_app.status THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_old_status_code IS NULL THEN
    v_old_status_code := lower(regexp_replace(COALESCE(v_app.status, ''), '[^a-zA-Z0-9]+', '_', 'g'));
    v_old_status_terminal := false;
  END IF;

  IF v_old_status_code = 'confirmed_onboard' AND v_level < 100 THEN
    RAISE EXCEPTION 'applicant is onboarded; only Super Admin may update applicant pipeline fields'
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(v_old_status_terminal, false) AND p_new_status IS NOT NULL AND v_level < 100 THEN
    RAISE EXCEPTION 'cannot change status from terminal status % without Super Admin override', v_app.status
      USING ERRCODE = '42501';
  END IF;

  IF (p_new_status IS NOT NULL OR p_follow_up_date IS NOT NULL)
     AND NOT (v_level = 100 OR public.i_am_recruitment() OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'only Recruitment, HRCO/ATL/TL/OM, or Super Admin may update status or follow_up_date'
      USING ERRCODE = '42501';
  END IF;

  IF (p_recruitment_remarks IS NOT NULL OR COALESCE(p_clear_recruitment_remarks, false))
     AND NOT (v_level = 100 OR public.i_am_recruitment()) THEN
    RAISE EXCEPTION 'only Recruitment or Super Admin may update recruitment_remarks'
      USING ERRCODE = '42501';
  END IF;

  IF (p_ops_remarks IS NOT NULL OR COALESCE(p_clear_ops_remarks, false))
     AND NOT (v_level = 100 OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'only HRCO/ATL/TL/OM or Super Admin may update ops_remarks'
      USING ERRCODE = '42501';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'applicants'
      AND column_name = 'deployed_reliever'
  )
  INTO v_has_deployed_reliever;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'applicants'
      AND column_name = 'deployed_commando'
  )
  INTO v_has_deployed_commando;

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
        aso.status_code = p_new_status
        OR aso.status_code = v_new_status_code
        OR aso.label = p_new_status
      )
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'unknown or inactive applicant status: %', p_new_status
        USING ERRCODE = '22023';
    END IF;

    IF v_new_status.is_system_only AND v_level < 100 THEN
      RAISE EXCEPTION 'status % is system-managed and cannot be set manually', v_new_status.status_code
        USING ERRCODE = '42501';
    END IF;

    IF v_new_status.status_code = 'new'
       AND COALESCE(v_old_status_code, '') <> 'new'
       AND v_level < 100 THEN
      RAISE EXCEPTION 'return to Sourcing is blocked; Super Admin override required'
        USING ERRCODE = '42501';
    END IF;

    v_new_status_label := v_new_status.label;
    v_status_changed := v_new_status_label IS DISTINCT FROM v_app.status;
  END IF;

  v_old_follow_up_date := v_app.follow_up_date;
  v_new_follow_up_date := COALESCE(p_follow_up_date, v_old_follow_up_date);
  v_follow_up_changed := p_follow_up_date IS NOT NULL
    AND v_new_follow_up_date IS DISTINCT FROM v_old_follow_up_date;

  v_old_recruitment_remarks := v_app.recruitment_remarks;
  IF COALESCE(p_clear_recruitment_remarks, false) THEN
    v_new_recruitment_remarks := NULL;
    v_recruitment_remarks_changed := v_old_recruitment_remarks IS NOT NULL;
  ELSIF p_recruitment_remarks IS NOT NULL THEN
    v_new_recruitment_remarks := p_recruitment_remarks;
    v_recruitment_remarks_changed := v_new_recruitment_remarks IS DISTINCT FROM v_old_recruitment_remarks;
  ELSE
    v_new_recruitment_remarks := v_old_recruitment_remarks;
  END IF;

  v_old_ops_remarks := v_app.ops_remarks;
  IF COALESCE(p_clear_ops_remarks, false) THEN
    v_new_ops_remarks := NULL;
    v_ops_remarks_changed := v_old_ops_remarks IS NOT NULL;
  ELSIF p_ops_remarks IS NOT NULL THEN
    v_new_ops_remarks := p_ops_remarks;
    v_ops_remarks_changed := v_new_ops_remarks IS DISTINCT FROM v_old_ops_remarks;
  ELSE
    v_new_ops_remarks := v_old_ops_remarks;
  END IF;

  IF v_has_deployed_reliever THEN
    v_old_deployed_reliever := (to_jsonb(v_app)->>'deployed_reliever')::boolean;
    v_deployed_reliever_changed := p_deployed_reliever IS NOT NULL
      AND p_deployed_reliever IS DISTINCT FROM v_old_deployed_reliever;
  END IF;

  IF v_has_deployed_commando THEN
    v_old_deployed_commando := (to_jsonb(v_app)->>'deployed_commando')::boolean;
    v_deployed_commando_changed := p_deployed_commando IS NOT NULL
      AND p_deployed_commando IS DISTINCT FROM v_old_deployed_commando;
  END IF;

  v_change_count :=
    CASE WHEN v_status_changed THEN 1 ELSE 0 END +
    CASE WHEN v_follow_up_changed THEN 1 ELSE 0 END +
    CASE WHEN v_recruitment_remarks_changed THEN 1 ELSE 0 END +
    CASE WHEN v_ops_remarks_changed THEN 1 ELSE 0 END +
    CASE WHEN v_deployed_reliever_changed THEN 1 ELSE 0 END +
    CASE WHEN v_deployed_commando_changed THEN 1 ELSE 0 END;

  IF v_change_count = 0 THEN
    RAISE EXCEPTION 'no applicant pipeline field values changed'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.applicants
  SET status = CASE WHEN v_status_changed THEN v_new_status_label ELSE status END,
      follow_up_date = CASE WHEN v_follow_up_changed THEN v_new_follow_up_date ELSE follow_up_date END,
      recruitment_remarks = CASE
        WHEN v_recruitment_remarks_changed THEN v_new_recruitment_remarks
        ELSE recruitment_remarks
      END,
      ops_remarks = CASE
        WHEN v_ops_remarks_changed THEN v_new_ops_remarks
        ELSE ops_remarks
      END,
      last_activity_at = v_now,
      last_activity_by = v_profile_id,
      last_activity_by_name = v_actor_name,
      updated_at = v_now,
      updated_by = v_profile_id
  WHERE id = p_applicant_id;

  IF v_deployed_reliever_changed THEN
    EXECUTE 'UPDATE public.applicants SET deployed_reliever = $1 WHERE id = $2'
    USING p_deployed_reliever, p_applicant_id;
  END IF;

  IF v_deployed_commando_changed THEN
    EXECUTE 'UPDATE public.applicants SET deployed_commando = $1 WHERE id = $2'
    USING p_deployed_commando, p_applicant_id;
  END IF;

  IF v_status_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, changed_by_name
    ) VALUES (
      v_history_id, p_applicant_id, v_app.status, v_new_status_label,
      p_reason_id, p_reason_type, NULL, v_profile_id, v_now, 'vacancy',
      'status_change', 'status', v_app.status, v_new_status_label, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
  END IF;

  IF v_follow_up_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_follow_up_date, new_follow_up_date,
      changed_by_name
    ) VALUES (
      v_history_id, p_applicant_id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'follow_up_update',
      'follow_up_date', v_old_follow_up_date::text, v_new_follow_up_date::text,
      v_old_follow_up_date, v_new_follow_up_date, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
  END IF;

  IF v_recruitment_remarks_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_recruitment_remarks,
      new_recruitment_remarks, changed_by_name
    ) VALUES (
      v_history_id, p_applicant_id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'recruitment_remarks_update',
      'recruitment_remarks', v_old_recruitment_remarks, v_new_recruitment_remarks,
      v_old_recruitment_remarks, v_new_recruitment_remarks, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
  END IF;

  IF v_ops_remarks_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_ops_remarks, new_ops_remarks,
      changed_by_name
    ) VALUES (
      v_history_id, p_applicant_id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'ops_remarks_update',
      'ops_remarks', v_old_ops_remarks, v_new_ops_remarks,
      v_old_ops_remarks, v_new_ops_remarks, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
  END IF;

  IF v_deployed_reliever_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_deployed_reliever,
      new_deployed_reliever, changed_by_name
    ) VALUES (
      v_history_id, p_applicant_id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'deployed_reliever_update',
      'deployed_reliever', v_old_deployed_reliever::text, p_deployed_reliever::text,
      v_old_deployed_reliever, p_deployed_reliever, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
  END IF;

  IF v_deployed_commando_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_deployed_commando,
      new_deployed_commando, changed_by_name
    ) VALUES (
      v_history_id, p_applicant_id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'deployed_commando_update',
      'deployed_commando', v_old_deployed_commando::text, p_deployed_commando::text,
      v_old_deployed_commando, p_deployed_commando, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'applicant_id', p_applicant_id,
    'updated_status', CASE WHEN v_status_changed THEN v_new_status_label ELSE v_app.status END,
    'last_activity_at', v_now,
    'last_activity_by', v_profile_id,
    'last_activity_by_name', v_actor_name,
    'history_ids', to_jsonb(v_history_ids),
    'changed_fields', (
      SELECT jsonb_agg(x.field_name ORDER BY x.sort_order)
      FROM (
        VALUES
          (1, 'status', v_status_changed),
          (2, 'follow_up_date', v_follow_up_changed),
          (3, 'recruitment_remarks', v_recruitment_remarks_changed),
          (4, 'ops_remarks', v_ops_remarks_changed),
          (5, 'deployed_reliever', v_deployed_reliever_changed),
          (6, 'deployed_commando', v_deployed_commando_changed)
      ) AS x(sort_order, field_name, changed)
      WHERE x.changed
    )
  );
END;
$$;

COMMENT ON FUNCTION public.fn_update_applicant_pipeline(
  uuid, text, date, text, text, boolean, boolean, uuid, text, boolean, boolean
) IS
  'SEAM 2 manual applicant pipeline update RPC. Stores UTC timestamptz, writes one applicant_status_history row per changed field, enforces Recruitment/Ops ownership, HA read-only, onboard lock, terminal source lock, and Sourcing return block. Does not mutate slots, CGCODE objects, or Plantilla lifecycle.';

REVOKE ALL ON FUNCTION public.fn_update_applicant_pipeline(
  uuid, text, date, text, text, boolean, boolean, uuid, text, boolean, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_update_applicant_pipeline(
  uuid, text, date, text, text, boolean, boolean, uuid, text, boolean, boolean
) TO authenticated, service_role;

-- ============================================================
-- 4. Validation queries
-- ============================================================
-- Run manually after applying. This migration was not applied by Codex.

-- V1 - applicants field existence
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name = 'applicants'
--   AND column_name IN (
--     'follow_up_date', 'recruitment_remarks', 'ops_remarks',
--     'last_activity_at', 'last_activity_by', 'last_activity_by_name'
--   )
-- ORDER BY column_name;
-- Expected: 6 rows; follow_up_date is_nullable='NO' and default includes CURRENT_DATE.

-- V2 - follow_up_date not null
-- SELECT count(*) AS null_follow_up_date_count
-- FROM public.applicants
-- WHERE follow_up_date IS NULL;
-- Expected: 0.

-- V3 - remarks backfill
-- SELECT count(*) AS missing_backfill_count
-- FROM public.applicants
-- WHERE remarks IS NOT NULL
--   AND btrim(remarks) <> ''
--   AND recruitment_remarks IS DISTINCT FROM remarks;
-- Expected: 0, except rows deliberately edited between migration start and validation.

-- V4 - history extension
-- SELECT column_name, data_type
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name = 'applicant_status_history'
--   AND column_name IN (
--     'update_type', 'changed_field', 'old_value', 'new_value',
--     'old_recruitment_remarks', 'new_recruitment_remarks',
--     'old_ops_remarks', 'new_ops_remarks',
--     'old_follow_up_date', 'new_follow_up_date',
--     'old_deployed_reliever', 'new_deployed_reliever',
--     'old_deployed_commando', 'new_deployed_commando',
--     'changed_by_name'
--   )
-- ORDER BY column_name;
-- Expected: 15 rows.

-- V5 - RPC signature
-- SELECT proname, pg_get_function_arguments(oid) AS args
-- FROM pg_proc
-- WHERE pronamespace = 'public'::regnamespace
--   AND proname = 'fn_update_applicant_pipeline';
-- Expected: one 11-argument signature matching this migration.

-- V6 - Recruitment can edit status/recruitment remarks/follow-up
-- -- Run as Recruitment, using an in-scope non-onboarded, non-terminal applicant:
-- SELECT public.fn_update_applicant_pipeline(
--   p_applicant_id => '<applicant_uuid>',
--   p_new_status => 'pooling',
--   p_follow_up_date => CURRENT_DATE + 1,
--   p_recruitment_remarks => 'Recruitment validation note'
-- );
-- Expected: success true; changed_fields contains status, follow_up_date, recruitment_remarks.

-- V7 - Ops can edit status/ops remarks/follow-up
-- -- Run as HRCO/ATL/TL/OM:
-- SELECT public.fn_update_applicant_pipeline(
--   p_applicant_id => '<applicant_uuid>',
--   p_new_status => 'for_interview',
--   p_follow_up_date => CURRENT_DATE + 2,
--   p_ops_remarks => 'Ops validation note'
-- );
-- Expected: success true; changed_fields contains status, follow_up_date, ops_remarks.

-- V8 - HA blocked
-- -- Run as Head Admin:
-- SELECT public.fn_update_applicant_pipeline(
--   p_applicant_id => '<applicant_uuid>',
--   p_follow_up_date => CURRENT_DATE + 3
-- );
-- Expected: 42501 Head Admin is read-only.

-- V9 - SA override
-- -- Run as Super Admin against an onboarded or terminal applicant:
-- SELECT public.fn_update_applicant_pipeline(
--   p_applicant_id => '<locked_applicant_uuid>',
--   p_new_status => 'pooling'
-- );
-- Expected: success true.

-- V10 - onboard lock
-- -- Run as non-SA against an applicant whose current status resolves to confirmed_onboard:
-- SELECT public.fn_update_applicant_pipeline(
--   p_applicant_id => '<confirmed_onboard_applicant_uuid>',
--   p_ops_remarks => 'blocked update'
-- );
-- Expected: 42501 onboarded lock error.

-- V11 - Sourcing return block
-- -- Run as non-SA against an applicant past Sourcing:
-- SELECT public.fn_update_applicant_pipeline(
--   p_applicant_id => '<past_sourcing_applicant_uuid>',
--   p_new_status => 'new'
-- );
-- Expected: 42501 return to Sourcing is blocked.

-- V12 - history rows created per changed field
-- SELECT changed_field, update_type, old_value, new_value, changed_by, changed_by_name, changed_at
-- FROM public.applicant_status_history
-- WHERE applicant_id = '<applicant_uuid>'
-- ORDER BY changed_at DESC
-- LIMIT 10;
-- Expected: one row per changed field from the last RPC call.

-- V13 - last_activity updated
-- SELECT last_activity_at, last_activity_by, last_activity_by_name, updated_at
-- FROM public.applicants
-- WHERE id = '<applicant_uuid>';
-- Expected: last_activity_at equals the RPC result timestamp and last_activity_by is the actor profile id.

-- V14 - no CGCODE or slot regressions: no objects changed by this migration
-- SELECT count(*) AS cgcode_vacancy_count
-- FROM public.vacancies
-- WHERE vcode LIKE 'CG-%';
-- Expected: informational only; this migration does not touch CGCODE rows.
--
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND tablename = 'applicants'
--   AND indexname IN (
--     'uq_applicants_one_active_per_slot',
--     'uq_applicants_one_active_per_coverage_slot'
--   );
-- Expected: existing slot uniqueness indexes remain present; this migration does not drop or recreate them.
