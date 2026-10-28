-- Migration: 20261028150500_hr_emploc_overhaul_and_deployment_sync.sql
-- Description:
--   1. Deployed tab & summary counter sync in get_web_hr_emploc_summary and list_web_hr_emplocs
--   2. Ecosystem-wide employee ID uniqueness validation (SECURITY DEFINER)
--   3. Inherited HRCO lookup by account & group (SECURITY DEFINER)
--   4. Edit Emploc (typo in employee ID) with simultaneous hr_emploc & plantilla sync
--   5. Revert to Pending with plantilla removal, ID hard-clearing, and vacancy reconciliation

BEGIN;

-- ============================================================================
-- 1. Ecosystem-wide Employee ID Uniqueness Check
-- ============================================================================
CREATE OR REPLACE FUNCTION public.check_ecosystem_employee_id_unique(
  p_employee_id text,
  p_exclude_hr_emploc_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_clean text := lower(btrim(coalesce(p_employee_id, '')));
  v_match_name text;
  v_match_module text;
BEGIN
  IF v_clean = '' THEN
    RETURN jsonb_build_object(
      'is_unique', false,
      'error', 'Employee ID is required.'
    );
  END IF;

  -- 1. Check hr_emploc (excluding the target record being edited)
  SELECT applicant_name, 'HR Emploc'
  INTO v_match_name, v_match_module
  FROM public.hr_emploc
  WHERE (lower(btrim(coalesce(employee_no, ''))) = v_clean OR lower(btrim(coalesce(emploc_no, ''))) = v_clean)
    AND (p_exclude_hr_emploc_id IS NULL OR id <> p_exclude_hr_emploc_id)
    AND deleted_at IS NULL
    AND status <> 'Backout'
  LIMIT 1;

  IF v_match_name IS NOT NULL THEN
    RETURN jsonb_build_object(
      'is_unique', false,
      'existing_name', v_match_name,
      'existing_module', v_match_module,
      'message', format('Employee ID %s is already assigned to %s (%s). Duplicate Emploc numbers are not allowed.', p_employee_id, v_match_name, v_match_module)
    );
  END IF;

  -- 2. Check plantilla (active & separated employees)
  SELECT coalesce(employee_name_snapshot, employee_name), 'Plantilla'
  INTO v_match_name, v_match_module
  FROM public.plantilla
  WHERE (lower(btrim(coalesce(employee_no, ''))) = v_clean OR lower(btrim(coalesce(emploc_no, ''))) = v_clean)
    AND (p_exclude_hr_emploc_id IS NULL OR hr_emploc_id IS NULL OR hr_emploc_id <> p_exclude_hr_emploc_id)
    AND coalesce(is_deleted, false) = false
  LIMIT 1;

  IF v_match_name IS NOT NULL THEN
    RETURN jsonb_build_object(
      'is_unique', false,
      'existing_name', v_match_name,
      'existing_module', v_match_module,
      'message', format('Employee ID %s is already assigned to %s (%s). Duplicate Emploc numbers are not allowed.', p_employee_id, v_match_name, v_match_module)
    );
  END IF;

  -- 3. Check auth.users / users_profile
  SELECT up.full_name, 'User Management'
  INTO v_match_name, v_match_module
  FROM public.users_profile up
  JOIN auth.users au ON au.id = up.auth_user_id
  WHERE lower(btrim(coalesce(au.raw_user_meta_data->>'employee_id', au.raw_user_meta_data->>'employee_no', ''))) = v_clean
    AND up.archived_at IS NULL
  LIMIT 1;

  IF v_match_name IS NOT NULL THEN
    RETURN jsonb_build_object(
      'is_unique', false,
      'existing_name', v_match_name,
      'existing_module', v_match_module,
      'message', format('Employee ID %s is already assigned to %s (%s). Duplicate Emploc numbers are not allowed.', p_employee_id, v_match_name, v_match_module)
    );
  END IF;

  RETURN jsonb_build_object(
    'is_unique', true
  );
END;
$$;

REVOKE ALL ON FUNCTION public.check_ecosystem_employee_id_unique(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_ecosystem_employee_id_unique(text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.check_ecosystem_employee_id_unique(text, uuid) TO authenticated;

-- ============================================================================
-- 2. Inherited HRCO Lookup by Account & Group (SECURITY DEFINER)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_inherited_account_group_hrcos(
  p_account_id uuid DEFAULT NULL,
  p_group_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group_id uuid := p_group_id;
  v_hrcos jsonb;
BEGIN
  IF v_group_id IS NULL AND p_account_id IS NOT NULL THEN
    SELECT group_id INTO v_group_id FROM public.accounts WHERE id = p_account_id;
  END IF;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', up.id,
        'full_name', up.full_name,
        'email', up.email
      ) ORDER BY up.full_name
    ),
    '[]'::jsonb
  )
  INTO v_hrcos
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE r.role_name = 'HRCO'
    AND coalesce(up.is_active, true) = true
    AND up.archived_at IS NULL
    AND (
      (p_account_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.user_scopes us WHERE us.user_id = up.id AND us.account_id = p_account_id
      ))
      OR (v_group_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.user_scopes us WHERE us.user_id = up.id AND us.group_id = v_group_id
      ))
      OR (p_account_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.accounts a WHERE a.id = p_account_id AND a.hrco_user_id = up.id
      ))
      OR up.hrco_global_visibility = true
    );

  RETURN v_hrcos;
END;
$$;

REVOKE ALL ON FUNCTION public.get_inherited_account_group_hrcos(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_inherited_account_group_hrcos(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_inherited_account_group_hrcos(uuid, uuid) TO authenticated;

-- Fast batch map of all active HRCOs for all accounts and groups
CREATE OR REPLACE FUNCTION public.get_all_account_group_hrcos_map()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
BEGIN
  WITH hrco_users AS (
    SELECT
      up.id AS profile_id,
      up.full_name,
      up.email,
      up.hrco_global_visibility,
      array_remove(array_agg(DISTINCT us.account_id), NULL) AS account_ids,
      array_remove(array_agg(DISTINCT us.group_id), NULL) AS group_ids
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    LEFT JOIN public.user_scopes us ON us.user_id = up.id
    WHERE r.role_name = 'HRCO'
      AND coalesce(up.is_active, true) = true
      AND up.archived_at IS NULL
    GROUP BY up.id, up.full_name, up.email, up.hrco_global_visibility
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'profile_id', hu.profile_id,
      'full_name', hu.full_name,
      'email', hu.email,
      'hrco_global_visibility', hu.hrco_global_visibility,
      'account_ids', hu.account_ids,
      'group_ids', hu.group_ids
    )
  )
  INTO v_result
  FROM hrco_users hu;

  RETURN coalesce(v_result, '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.get_all_account_group_hrcos_map() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_all_account_group_hrcos_map() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_all_account_group_hrcos_map() TO authenticated;

-- ============================================================================
-- 3. Edit Deployed Emploc (Typo Fix in Employee ID)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_deployed_employee_id(
  p_hr_emploc_id uuid,
  p_new_employee_no text,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor_profile_id uuid := public.get_my_profile_id();
  v_actor_name       text := public.get_my_full_name();
  v_clean_id         text := btrim(coalesce(p_new_employee_no, ''));
  v_reason           text := btrim(coalesce(p_reason, ''));
  v_emp              public.hr_emploc;
  v_old_id           text;
  v_check            jsonb;
BEGIN
  IF v_clean_id = '' THEN
    RAISE EXCEPTION 'New Employee ID is required' USING ERRCODE = '22023';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Reason for edit is required' USING ERRCODE = '22023';
  END IF;

  IF NOT (public.i_have_full_access() OR public.get_my_role() = 'Encoder' OR public.i_am_hr_dept()) THEN
    RAISE EXCEPTION 'forbidden: Super Admin, Data Team, or HR Personnel required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Record not found or archived' USING ERRCODE = 'P0002';
  END IF;

  v_old_id := v_emp.employee_no;

  -- Ecosystem uniqueness check (excluding current record)
  v_check := public.check_ecosystem_employee_id_unique(v_clean_id, p_hr_emploc_id);
  IF (v_check->>'is_unique')::boolean = false THEN
    RAISE EXCEPTION '%', (v_check->>'message') USING ERRCODE = '23505';
  END IF;

  -- Update hr_emploc
  UPDATE public.hr_emploc
  SET employee_no = v_clean_id,
      emploc_no   = v_clean_id,
      updated_at  = now(),
      updated_by  = v_actor_profile_id
  WHERE id = p_hr_emploc_id;

  -- Update plantilla row
  UPDATE public.plantilla
  SET employee_no = v_clean_id,
      emploc_no   = v_clean_id,
      updated_at  = now(),
      updated_by  = v_actor_profile_id
  WHERE hr_emploc_id = p_hr_emploc_id
     OR (v_old_id IS NOT NULL AND employee_no = v_old_id);

  -- Log Activity History Trail
  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    jsonb_build_object('employee_no', v_old_id),
    jsonb_build_object(
      'employee_no', v_clean_id,
      'reason', v_reason,
      'log_message', format('Updated Employee ID from %s to %s (Reason: %s) by %s', coalesce(v_old_id, 'None'), v_clean_id, v_reason, v_actor_name)
    )
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'old_id', v_old_id,
    'new_id', v_clean_id,
    'message', format('Updated Employee ID from %s to %s', coalesce(v_old_id, 'None'), v_clean_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.update_deployed_employee_id(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_deployed_employee_id(uuid, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_deployed_employee_id(uuid, text, text) TO authenticated;

-- ============================================================================
-- 4. Revert to Pending (Wrong Applicant Encoded) with Vacancy Reconciliation
-- ============================================================================
CREATE OR REPLACE FUNCTION public.revert_hr_emploc_to_pending(
  p_hr_emploc_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor_profile_id uuid := public.get_my_profile_id();
  v_actor_name       text := public.get_my_full_name();
  v_reason           text := btrim(coalesce(p_reason, ''));
  v_emp              public.hr_emploc;
  v_pl               public.plantilla;
  v_old_employee_no  text;
  v_vacancy_id       uuid;
  v_vcode            text;
  v_active_plantilla_count int;
  v_req_headcount    int;
BEGIN
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Reason for revert is required' USING ERRCODE = '22023';
  END IF;

  IF NOT (public.i_have_full_access() OR public.get_my_role() = 'Encoder' OR public.i_am_hr_dept()) THEN
    RAISE EXCEPTION 'forbidden: Super Admin, Data Team, or HR Personnel required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Record not found or archived' USING ERRCODE = 'P0002';
  END IF;

  v_old_employee_no := v_emp.employee_no;
  v_vacancy_id      := v_emp.vacancy_id;
  v_vcode           := v_emp.vcode;

  -- 1. Unlink and remove from active Plantilla
  SELECT * INTO v_pl FROM public.plantilla
  WHERE hr_emploc_id = p_hr_emploc_id
     OR (v_old_employee_no IS NOT NULL AND employee_no = v_old_employee_no)
  LIMIT 1;

  IF v_pl.id IS NOT NULL THEN
    -- Soft-delete / unlink the plantilla row
    UPDATE public.plantilla
    SET is_deleted = true,
        status     = 'Separated',
        updated_at = now(),
        updated_by = v_actor_profile_id
    WHERE id = v_pl.id;

    -- If roving store links exist, mark deleted
    UPDATE public.plantilla_store_links
    SET status = 'Deleted',
        updated_at = now(),
        updated_by = v_actor_profile_id
    WHERE plantilla_id = v_pl.id;

    -- If slot was occupied by this plantilla row, reset slot to open/pipeline
    UPDATE public.plantilla_slots
    SET slot_status = 'open',
        occupied_by_plantilla_id = NULL,
        hr_emploc_id = NULL,
        updated_at = now()
    WHERE occupied_by_plantilla_id = v_pl.id;
  END IF;

  -- 2. Vacancy Status Reconciliation
  -- If this vacancy was marked 'Filled', check if active plantilla count is now below required headcount
  IF v_vcode IS NOT NULL THEN
    SELECT required_headcount INTO v_req_headcount
    FROM public.vacancies
    WHERE vcode = v_vcode AND deleted_at IS NULL
    LIMIT 1;

    SELECT count(*) INTO v_active_plantilla_count
    FROM public.plantilla
    WHERE vcode = v_vcode
      AND coalesce(is_deleted, false) = false
      AND status IN ('Active', 'On Leave');

    IF v_req_headcount IS NOT NULL AND coalesce(v_active_plantilla_count, 0) < v_req_headcount THEN
      -- Reopen the vacancy
      UPDATE public.vacancies
      SET status = 'Open',
          updated_at = now(),
          updated_by = v_actor_profile_id
      WHERE vcode = v_vcode
        AND status IN ('Filled', 'Closed')
        AND coalesce(is_archived, false) = false
        AND deleted_at IS NULL;
    END IF;
  END IF;

  -- 3. Hard-clear employee_no and revert hr_emploc status
  UPDATE public.hr_emploc
  SET employee_no            = NULL,
      emploc_no              = NULL,
      status                 = 'Pending Emploc',
      hr_status              = 'Pending',
      moved_to_plantilla_at  = NULL,
      moved_to_plantilla_by  = NULL,
      updated_at             = now(),
      updated_by             = v_actor_profile_id
  WHERE id = p_hr_emploc_id;

  -- 4. Activity Log Entry
  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    jsonb_build_object('status', 'Moved to Plantilla', 'employee_no', v_old_employee_no),
    jsonb_build_object(
      'status', 'Pending Emploc',
      'employee_no', NULL,
      'reason', v_reason,
      'log_message', format('Reverted from Deployed to Pending and removed from Plantilla (Reason: %s) by %s', v_reason, v_actor_name)
    )
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'freed_employee_id', v_old_employee_no,
    'message', format('Reverted from Deployed to Pending and removed from Plantilla. Employee ID %s is now freed.', coalesce(v_old_employee_no, ''))
  );
END;
$$;

REVOKE ALL ON FUNCTION public.revert_hr_emploc_to_pending(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.revert_hr_emploc_to_pending(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.revert_hr_emploc_to_pending(uuid, text) TO authenticated;

-- ============================================================================
-- 5. Update list_web_hr_emplocs and get_web_hr_emploc_summary for Deployed Tab
-- ============================================================================

DROP FUNCTION IF EXISTS public.get_web_hr_emploc_summary(text, text, text, text, uuid, uuid, text);

-- A. Update get_web_hr_emploc_summary to count Deployed records
CREATE OR REPLACE FUNCTION public.get_web_hr_emploc_summary(
  p_queue         text DEFAULT NULL,
  p_status        text DEFAULT NULL,
  p_deficiency    text DEFAULT NULL,
  p_sla_filter    text DEFAULT NULL,
  p_account_id    uuid DEFAULT NULL,
  p_group_id      uuid DEFAULT NULL,
  p_search        text DEFAULT NULL
)
RETURNS TABLE (
  pending_count          bigint,
  correction_count       bigint,
  review_count           bigint,
  ready_count            bigint,
  deployed_count         bigint,
  sla_breached_count     bigint,
  sla_warning_count      bigint,
  with_deficiency_count  bigint,
  pending_deletion_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc summary requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_name, r.role_level
  INTO v_profile_id, v_role_name, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      h.hr_status,
      h.status,
      h.account_id,
      a.account_name,
      a.group_id,
      h.applicant_name,
      h.vcode,
      h.employee_no,
      h.emploc_no,
      h.store_name,
      h.position AS position_title,
      COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)) AS hrco_name,
      h.correction_reason,
      h.deleted_at,
      h.moved_to_plantilla_at,
      
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))) AS sla_breached,
      
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval)) AS sla_warning,
      
      CASE
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))
          THEN 'breached'
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval))
          THEN 'warning'
        ELSE 'normal'
      END AS sla_status
    FROM public.hr_emploc h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    WHERE
      h.deleted_at IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.account = ANY (public.get_my_allowed_accounts())
          OR
          EXISTS (
            SELECT 1 FROM public.user_scopes us
            WHERE us.user_id = v_profile_id AND us.account_id = h.account_id
          )
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = h.account_id
            WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
          )
          OR EXISTS (
            SELECT 1 FROM public.users_profile up_fallback JOIN public.accounts ac ON ac.id = h.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
              AND (up_fallback.account_id = h.account_id OR up_fallback.group_id = ac.group_id)
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      (p_deficiency IS NULL
       OR (p_deficiency = 'any' AND s.correction_reason IS NOT NULL)
       OR (p_deficiency = 'none' AND s.correction_reason IS NULL)
       OR (
         s.correction_reason IS NOT NULL AND (
           (jsonb_typeof(s.correction_reason) = 'array' AND EXISTS (
             SELECT 1 FROM jsonb_array_elements(s.correction_reason) el
             WHERE el->>'code' = p_deficiency
           ))
           OR
           (jsonb_typeof(s.correction_reason) = 'object' AND s.correction_reason->>'type' = p_deficiency)
         )
       )
      )
      AND (p_sla_filter IS NULL OR s.sla_status = p_sla_filter)
      AND (p_status IS NULL OR s.status = p_status)
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.applicant_name ILIKE '%' || btrim(p_search) || '%'
        OR s.employee_no ILIKE '%' || btrim(p_search) || '%'
        OR s.emploc_no ILIKE '%' || btrim(p_search) || '%'
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
        OR s.hrco_name ILIKE '%' || btrim(p_search) || '%'
        OR s.hr_status ILIKE '%' || btrim(p_search) || '%'
        OR s.status ILIKE '%' || btrim(p_search) || '%'
      )
  )
  SELECT
    count(*) FILTER (WHERE f.hr_status = 'Pending' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS pending_count,
    count(*) FILTER (WHERE f.hr_status = 'For Correction' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS correction_count,
    count(*) FILTER (WHERE f.hr_status = 'For Review' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS review_count,
    count(*) FILTER (WHERE (
      f.status IN ('Moved to Plantilla', 'Deployed', 'Employee No Assigned', 'Ready for Plantilla')
      OR f.hr_status IN ('Transferred', 'Ready', 'Deployed', 'Complete')
      OR f.moved_to_plantilla_at IS NOT NULL
      OR (f.employee_no IS NOT NULL AND btrim(f.employee_no) <> '')
    ) AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS ready_count,
    count(*) FILTER (WHERE (
      f.status IN ('Moved to Plantilla', 'Deployed', 'Employee No Assigned', 'Ready for Plantilla')
      OR f.hr_status IN ('Transferred', 'Ready', 'Deployed', 'Complete')
      OR f.moved_to_plantilla_at IS NOT NULL
      OR (f.employee_no IS NOT NULL AND btrim(f.employee_no) <> '')
    ) AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS deployed_count,
    count(*) FILTER (WHERE f.sla_breached = true)::bigint AS sla_breached_count,
    count(*) FILTER (WHERE f.sla_warning = true)::bigint AS sla_warning_count,
    count(*) FILTER (WHERE f.correction_reason IS NOT NULL)::bigint AS with_deficiency_count,
    count(*) FILTER (WHERE f.hr_status = 'Pending Deletion' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS pending_deletion_count
  FROM filtered f;
END;
$$;

REVOKE ALL ON FUNCTION public.get_web_hr_emploc_summary(text, text, text, text, uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_web_hr_emploc_summary(text, text, text, text, uuid, uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_web_hr_emploc_summary(text, text, text, text, uuid, uuid, text) TO authenticated;

DROP FUNCTION IF EXISTS public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text);

-- B. Update list_web_hr_emplocs to support 'deployed' queue
CREATE OR REPLACE FUNCTION public.list_web_hr_emplocs(
  p_queue         text DEFAULT NULL,
  p_status        text DEFAULT NULL,
  p_deficiency    text DEFAULT NULL,
  p_sla_filter    text DEFAULT NULL,
  p_account_id    uuid DEFAULT NULL,
  p_group_id      uuid DEFAULT NULL,
  p_search        text DEFAULT NULL,
  p_limit         integer DEFAULT 50,
  p_offset        integer DEFAULT 0,
  p_sort_by       text DEFAULT 'date_requested',
  p_sort_dir      text DEFAULT 'desc'
)
RETURNS TABLE (
  hr_emploc_id          uuid,
  applicant_name        text,
  vcode                 text,
  account_id            uuid,
  account_name          text,
  group_id              uuid,
  group_name            text,
  store_id              uuid,
  store_name            text,
  position_title        text,
  hr_status             text,
  status                text,
  emploc_no             text,
  employee_no           text,
  date_requested        timestamp with time zone,
  created_at            timestamp with time zone,
  hired_date            date,
  assignment_type       text,
  roving_assignment_id  uuid,
  aging_days            integer,
  sla_breached          boolean,
  sla_status            text,
  sla_deadline          timestamp with time zone,
  deficiency_summary    jsonb,
  is_pending_deletion   boolean,
  row_capabilities      jsonb,
  total_count           bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
  v_sort_by      text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'date_requested'));
  v_sort_dir     text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'desc'));
  v_limit        integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset       integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc list requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_name, r.role_level
  INTO   v_profile_id, v_role_name, v_role_level
  FROM   public.users_profile up
  JOIN   public.roles r ON r.id = up.role_id
  WHERE  up.auth_user_id = v_auth_uid
    AND  up.is_active = TRUE
    AND  up.archived_at IS NULL
  ORDER  BY up.created_at DESC
  LIMIT  1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      h.id AS hr_emploc_id,
      h.applicant_name,
      h.vcode,
      h.account_id,
      a.account_name,
      a.group_id,
      g.group_name,
      h.store_id,
      h.store_name,
      h.position AS position_title,
      COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)) AS hrco_name,
      h.hr_status,
      h.status,
      h.emploc_no,
      h.employee_no,
      h.date_requested,
      h.created_at,
      h.hired_date,
      h.assignment_type::text AS assignment_type,
      h.roving_assignment_id,
      h.deleted_at,
      h.moved_to_plantilla_at,
      
      GREATEST(0, (EXTRACT(day FROM (now() - COALESCE(h.date_requested, h.created_at))))::integer) AS aging_days,
      
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))) AS sla_breached,
      
      CASE
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))
          THEN 'breached'
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval))
          THEN 'warning'
        ELSE 'normal'
      END AS sla_status,
      
      (COALESCE(h.date_requested, h.created_at) + INTERVAL '3 days') AS sla_deadline,
      
      CASE
        WHEN h.correction_reason IS NULL THEN jsonb_build_object('active_count', 0, 'issues', '[]'::jsonb)
        ELSE jsonb_build_object(
          'active_count', CASE WHEN jsonb_typeof(h.correction_reason) = 'array' THEN jsonb_array_length(h.correction_reason) ELSE 1 END,
          'issues', CASE
            WHEN jsonb_typeof(h.correction_reason) = 'array' THEN (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'code', el->>'code',
                  'comment', el->>'comment',
                  'label', COALESCE((SELECT it.label FROM public.hr_emploc_issue_types it WHERE it.code = el->>'code'), el->>'code')
                )
              )
              FROM jsonb_array_elements(h.correction_reason) el
            )
            ELSE jsonb_build_array(
              jsonb_build_object(
                'code', h.correction_reason->>'type',
                'comment', h.correction_reason->>'comment',
                'label', COALESCE((SELECT it.label FROM public.hr_emploc_issue_types it WHERE it.code = h.correction_reason->>'type'), h.correction_reason->>'type')
              )
            )
          END
        )
      END AS deficiency_summary,
      
      EXISTS (
        SELECT 1 FROM public.hr_emploc_deletion_requests dr
        WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
      ) AS is_pending_deletion,
      
      jsonb_build_object(
        'can_view_detail', true,
        'hrco_name', COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)),
        'can_edit_emploc', (
          (v_role_level >= 30 OR v_role_name IN ('OM', 'HRCO', 'Encoder') OR public.i_am_hr_dept() OR public.i_have_full_access())
          AND (h.status = 'Moved to Plantilla' OR h.hr_status IN ('Transferred', 'Deployed', 'Complete') OR (h.employee_no IS NOT NULL AND btrim(h.employee_no) <> ''))
        ),
        'can_revert_to_pending', (
          (v_role_level >= 30 OR v_role_name IN ('OM', 'HRCO', 'Encoder') OR public.i_am_hr_dept() OR public.i_have_full_access())
          AND (h.status = 'Moved to Plantilla' OR h.hr_status IN ('Transferred', 'Deployed', 'Complete') OR (h.employee_no IS NOT NULL AND btrim(h.employee_no) <> ''))
        ),
        'can_request_deletion', (
          h.status <> 'Moved to Plantilla'
          AND h.hr_status <> 'Pending Deletion'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
          AND (v_role_level >= 70 OR v_role_name IN ('OM', 'HRCO', 'ATL', 'TL', 'ATL/TL') OR public.i_am_ops() OR public.i_have_full_access())
        ),
        'can_withdraw_deletion_request', (
          EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
          AND (
            public.i_have_full_access()
            OR EXISTS (
              SELECT 1 FROM public.hr_emploc_deletion_requests dr
              WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending' AND dr.requested_by_user_id = v_profile_id
            )
          )
        ),
        'can_review_deletion', (
          (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
          AND EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_approve_correction', (
          h.hr_status = 'For Review'
          AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        ),
        'can_revert_correction', (
          h.hr_status = 'For Review'
          AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        ),
        'can_review_correction', (
          (public.i_am_hr_dept() OR public.i_have_full_access())
          AND h.hr_status = 'For Review'
          AND h.status = 'Pending Emploc'
          AND NOT EXISTS (
            SELECT 1
            FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id
              AND dr.status = 'Pending'
          )
        ),
        'can_submit_correction', (
          h.hr_status = 'For Correction'
          AND (public.i_have_full_access() OR v_role_name = 'HRCO' OR h.hrco_user_id_snapshot = v_profile_id)
        ),
        'can_move_to_plantilla', (
          (h.hr_status = 'Complete' OR h.status = 'Ready for Plantilla')
          AND COALESCE(h.employee_no, '') <> ''
          AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        ),
        'can_tag_deficiency', (
          (public.i_am_hr_dept() OR public.i_have_full_access())
          AND h.status <> 'Moved to Plantilla'
          AND h.hr_status <> 'Complete'
          AND NOT EXISTS (
            SELECT 1
            FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id
              AND dr.status = 'Pending'
          )
        ),
        'can_assign_employee_no', (
          (v_role_name = 'Encoder' OR v_role_level >= 30 OR public.i_am_hr_dept() OR v_role_name IN ('OM', 'HRCO') OR public.i_have_full_access())
          AND COALESCE(h.employee_no, '') = ''
          AND h.status <> 'Moved to Plantilla'
          AND NOT EXISTS (
            SELECT 1
            FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id
              AND dr.status = 'Pending'
          )
        )
      ) AS row_capabilities
    FROM public.hr_emploc h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    LEFT JOIN public.groups g ON g.id = a.group_id
    WHERE
      h.deleted_at IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.account = ANY (public.get_my_allowed_accounts())
          OR
          EXISTS (
            SELECT 1 FROM public.user_scopes us
            WHERE us.user_id = v_profile_id AND us.account_id = h.account_id
          )
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = h.account_id
            WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
          )
          OR EXISTS (
            SELECT 1 FROM public.users_profile up_fallback JOIN public.accounts ac ON ac.id = h.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
              AND (up_fallback.account_id = h.account_id OR up_fallback.group_id = ac.group_id)
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      -- Queue Filter (including 'deployed' and 'ready')
      (p_queue IS NULL
       OR (p_queue = 'pending' AND s.hr_status = 'Pending' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue = 'correction' AND s.hr_status = 'For Correction' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue = 'review' AND s.hr_status = 'For Review' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue IN ('deployed', 'ready', 'complete', 'transferred') AND (
            s.status IN ('Moved to Plantilla', 'Deployed', 'Employee No Assigned', 'Ready for Plantilla')
            OR s.hr_status IN ('Transferred', 'Ready', 'Deployed', 'Complete')
            OR s.moved_to_plantilla_at IS NOT NULL
            OR (s.employee_no IS NOT NULL AND btrim(s.employee_no) <> '')
          )
          AND s.status <> 'Backout'
          AND s.deleted_at IS NULL
       )
       OR (p_queue = 'rejected' AND s.hr_status = 'Rejected' AND s.deleted_at IS NULL)
      )
      AND (p_deficiency IS NULL
       OR (p_deficiency = 'any' AND s.deficiency_summary->'active_count' > '0'::jsonb)
       OR (p_deficiency = 'none' AND s.deficiency_summary->'active_count' = '0'::jsonb)
       OR (
         s.deficiency_summary->'active_count' > '0'::jsonb AND EXISTS (
           SELECT 1 FROM jsonb_array_elements(s.deficiency_summary->'issues') el
           WHERE el->>'code' = p_deficiency
         )
       )
      )
      AND (p_sla_filter IS NULL OR s.sla_status = p_sla_filter)
      AND (p_status IS NULL OR s.status = p_status)
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.applicant_name ILIKE '%' || btrim(p_search) || '%'
        OR s.employee_no ILIKE '%' || btrim(p_search) || '%'
        OR s.emploc_no ILIKE '%' || btrim(p_search) || '%'
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
        OR s.hrco_name ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT f.*, count(*) OVER () AS total_count
    FROM filtered f
  )
  SELECT
    c.hr_emploc_id,
    c.applicant_name,
    c.vcode,
    c.account_id,
    c.account_name,
    c.group_id,
    c.group_name,
    c.store_id,
    c.store_name,
    c.position_title,
    c.hr_status,
    c.status,
    c.emploc_no,
    c.employee_no,
    c.date_requested,
    c.created_at,
    c.hired_date,
    c.assignment_type,
    c.roving_assignment_id,
    c.aging_days,
    c.sla_breached,
    c.sla_status,
    c.sla_deadline,
    c.deficiency_summary,
    c.is_pending_deletion,
    c.row_capabilities,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vcode'            THEN c.vcode END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vcode'            THEN c.vcode END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'applicant_name'   THEN c.applicant_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'applicant_name'   THEN c.applicant_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'account_name'     THEN c.account_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name'     THEN c.account_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'group_name'       THEN c.group_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name'       THEN c.group_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'store_name'       THEN c.store_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name'       THEN c.store_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'position_title'   THEN c.position_title END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'position_title'   THEN c.position_title END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'hr_status'        THEN c.hr_status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'hr_status'        THEN c.hr_status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'status'           THEN c.status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'status'           THEN c.status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'emploc_no'        THEN c.emploc_no END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'emploc_no'        THEN c.emploc_no END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'employee_no'      THEN c.employee_no END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'employee_no'      THEN c.employee_no END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'date_requested'   THEN c.date_requested END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'date_requested'   THEN c.date_requested END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'created_at'       THEN c.created_at END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'created_at'       THEN c.created_at END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'aging_days'       THEN c.aging_days END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'aging_days'       THEN c.aging_days END DESC NULLS LAST,
    c.created_at DESC NULLS LAST
  LIMIT v_limit
  OFFSET v_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text) TO authenticated;

COMMIT;
