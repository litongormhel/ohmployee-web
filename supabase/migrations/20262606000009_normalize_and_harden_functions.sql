-- Migration: 20262606000009_normalize_and_harden_functions
-- Created: 2026-07-02
-- Purpose: Normalize and security-harden the 14 vacancy-workflow / RBAC functions that
--          were reasserted verbatim (no CREATE FUNCTION in prior migration history) by
--          20262606000008_reassert_function_bodies.sql. No signature changes, no
--          renames, no behavioral changes. Idempotent CREATE OR REPLACE only.
--
-- Context (ohm#c4f8a91e — Step 5: Normalize & Harden Live Functions):
--   Canonical source selection per function: prefer
--   _legacy_unversioned/20260505_secure_vacancy_module.sql, compared against the
--   already-live-verified 20262606000008_reassert_function_bodies.sql. All 14 bodies
--   were confirmed byte-identical between the two sources (module 20260505 predates
--   and matches the live/reasserted state). Verified directly against live staging
--   (qqiiznmqxfoamqytjica) via pg_proc: volatility, SECURITY DEFINER, and existing
--   proconfig already match expectations for 10 of 14 functions (search_path already
--   set by 20262606000008). Only 4 functions were missing `search_path` hardening on
--   live staging and in every migration source:
--     - i_am_head_admin()
--     - i_am_hrco()
--     - i_am_om()
--     - fn_mask_vacancy_for_role(vacancies, text)
--   This migration adds `SET search_path = public` to those 4 and schema-qualifies
--   fn_mask_vacancy_for_role's parameter type (public.vacancies) for consistency with
--   the other 13. All other functions are reasserted verbatim (no behavioral change)
--   to bring the full set of 14 under a single deterministic, migration-controlled
--   definition.
--
-- Explicitly excluded (per task scope): fn_enforce_vacancy_transition, rls_auto_enable.
--
-- Grants: reapplied exactly as currently defined on live staging (GRANT ... TO
--   authenticated only) — no roles added, no access broadened. The default PUBLIC
--   EXECUTE grant present on all 14 functions (Postgres default; never explicitly
--   REVOKEd by any prior migration, including the 20260505 source) is a pre-existing,
--   schema-wide condition not introduced or altered by this migration and is out of
--   scope here — SECURITY DEFINER bodies self-guard via `get_my_profile_id() IS NULL`
--   checks. Flagged for a separate, deliberate REVOKE-PUBLIC pass if desired.
--
-- Zero behavioral changes. Zero DROP statements. Zero signature drift.
--
-- Smoke Tests:
-- S1: SELECT proconfig FROM pg_proc WHERE proname = 'i_am_head_admin'; -- expect search_path=public
-- S2: SELECT proconfig FROM pg_proc WHERE proname = 'i_am_hrco';       -- expect search_path=public
-- S3: SELECT proconfig FROM pg_proc WHERE proname = 'i_am_om';         -- expect search_path=public
-- S4: SELECT proconfig FROM pg_proc WHERE proname = 'fn_mask_vacancy_for_role'; -- expect search_path=public
-- S5: SELECT get_my_vacancies(NULL, 5, 0); -- as an authenticated test user, unchanged result set

BEGIN;

-- ---------------------------------------------------------------------
-- 1. RBAC / Scope helpers
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.i_am_head_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT get_my_role() = 'Head Admin';
$$;
GRANT EXECUTE ON FUNCTION public.i_am_head_admin() TO authenticated;

CREATE OR REPLACE FUNCTION public.i_am_hrco()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT get_my_role() = 'HRCO';
$$;
GRANT EXECUTE ON FUNCTION public.i_am_hrco() TO authenticated;

CREATE OR REPLACE FUNCTION public.i_am_om()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT get_my_role() = 'Operations Manager';
$$;
GRANT EXECUTE ON FUNCTION public.i_am_om() TO authenticated;

CREATE OR REPLACE FUNCTION public.i_have_account_scope(p_account_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.i_have_full_access() OR (p_account_id = ANY (public.get_my_allowed_account_ids()));
$$;
GRANT EXECUTE ON FUNCTION public.i_have_account_scope(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 2. Support helpers
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.i_am_assigned_to_vacancy(p_vacancy_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id UUID := public.get_my_profile_id();
  v_hit BOOLEAN;
BEGIN
  IF v_profile_id IS NULL THEN RETURN FALSE; END IF;
  SELECT TRUE INTO v_hit
  FROM public.vacancies
  WHERE id = p_vacancy_id
    AND (hrco_user_id        = v_profile_id
      OR om_user_id          = v_profile_id
      OR atl_user_id         = v_profile_id
      OR assigned_encoder_id = v_profile_id
      OR requested_by_user_id= v_profile_id
      OR created_by          = v_profile_id
      OR created_by_user_id  = v_profile_id);
  RETURN COALESCE(v_hit, FALSE);
END;
$$;
GRANT EXECUTE ON FUNCTION public.i_am_assigned_to_vacancy(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_mask_vacancy_for_role(p_row public.vacancies, p_role text)
RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
DECLARE
  v jsonb := to_jsonb(p_row);
BEGIN
  IF p_role = 'Encoder' THEN
    v := v
      - 'hrco_name' - 'hrco_mobile' - 'hrco_user_id'
      - 'om_name'   - 'om_user_id'
      - 'atl_user_id'
      - 'has_penalty' - 'penalty_amount' - 'penalty_aging_detail'
      - 'chain' - 'chain_id'
      - 'requested_by_user_id';
  END IF;
  RETURN v;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_mask_vacancy_for_role(public.vacancies, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 3. Vacancy Workflow RPCs
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_vacancy_request(
  p_account_id          uuid,
  p_store_id            uuid,
  p_position_id         uuid,
  p_vacancy_type        text     DEFAULT 'New',
  p_required_headcount  integer  DEFAULT 1,
  p_vacant_date         date     DEFAULT NULL,
  p_remarks             text     DEFAULT NULL,
  p_source_plantilla_id uuid     DEFAULT NULL,
  p_has_penalty         boolean  DEFAULT false,
  p_penalty_amount      numeric  DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id uuid := public.get_my_profile_id();
  v_role       text := public.get_my_role();
  v_role_lvl   int  := public.get_my_role_level();
  v_account    record;
  v_store      record;
  v_position   record;
  v_new_id     uuid;
  v_dup_id     uuid;
  v_plant      record;
BEGIN
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;

  IF v_role_lvl < 30 OR v_role IN ('Viewer','Back Office') THEN
    RAISE EXCEPTION 'Role % cannot create vacancies', v_role USING ERRCODE = '42501';
  END IF;

  IF NOT public.i_have_account_scope(p_account_id) THEN
    RAISE EXCEPTION 'Account % is outside your scope', p_account_id USING ERRCODE = '42501';
  END IF;

  SELECT a.* INTO v_account FROM public.accounts a WHERE a.id = p_account_id;
  IF NOT FOUND OR v_account.is_active IS NOT TRUE THEN
    RAISE EXCEPTION 'Account not found or inactive: %', p_account_id;
  END IF;

  SELECT s.* INTO v_store FROM public.stores s WHERE s.id = p_store_id;
  IF NOT FOUND OR COALESCE(v_store.is_active, true) = false THEN
    RAISE EXCEPTION 'Store not found or inactive: %', p_store_id;
  END IF;
  IF v_store.account_id IS NOT NULL AND v_store.account_id <> p_account_id THEN
    RAISE EXCEPTION 'Store % does not belong to account %', p_store_id, p_account_id;
  END IF;

  SELECT pos.* INTO v_position FROM public.positions pos WHERE pos.id = p_position_id;
  IF NOT FOUND OR COALESCE(v_position.is_active, true) = false THEN
    RAISE EXCEPTION 'Position not found or inactive: %', p_position_id;
  END IF;

  -- Plantilla integrity (if creating from existing slot)
  IF p_source_plantilla_id IS NOT NULL THEN
    SELECT pl.* INTO v_plant FROM public.plantilla pl WHERE pl.id = p_source_plantilla_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Source plantilla not found: %', p_source_plantilla_id;
    END IF;
    IF v_plant.account_id IS NOT NULL AND v_plant.account_id <> p_account_id THEN
      RAISE EXCEPTION 'Source plantilla account mismatch';
    END IF;
    IF v_plant.store_id IS NOT NULL AND v_plant.store_id <> p_store_id THEN
      RAISE EXCEPTION 'Source plantilla store mismatch';
    END IF;
    IF v_plant.position_id IS NOT NULL AND v_plant.position_id <> p_position_id THEN
      RAISE EXCEPTION 'Source plantilla position mismatch';
    END IF;
  END IF;

  -- Duplicate active vacancy guard
  SELECT v.id INTO v_dup_id
  FROM public.vacancies v
  WHERE v.store_id = p_store_id
    AND v.position_id = p_position_id
    AND v.status IN ('Draft','Pending Approval','Open','On Hold')
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
  LIMIT 1;

  IF v_dup_id IS NOT NULL THEN
    RAISE EXCEPTION 'Duplicate active vacancy already exists for this store/position (id=%)', v_dup_id
      USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO public.vacancies (
    account_id, store_id, position_id,
    account, store_name, position,
    vacancy_type, required_headcount, vacant_date,
    remarks, source_plantilla_id,
    has_penalty, penalty_amount,
    status, requested_by_user_id, created_by, created_by_user_id, requested_date
  ) VALUES (
    p_account_id, p_store_id, p_position_id,
    v_account.account_name, v_store.store_name, v_position.position_name,
    COALESCE(p_vacancy_type,'New'), GREATEST(p_required_headcount,1), p_vacant_date,
    p_remarks, p_source_plantilla_id,
    COALESCE(p_has_penalty,false), p_penalty_amount,
    'Draft', v_profile_id, v_profile_id, v_profile_id, CURRENT_DATE
  )
  RETURNING id INTO v_new_id;

  PERFORM public.log_audit_event(
    'vacancies', 'INSERT', v_new_id, NULL,
    jsonb_build_object('semantic_action','CREATE_VACANCY_REQUEST',
                       'actor_role', v_role,
                       'account_id', p_account_id,
                       'store_id',   p_store_id,
                       'position_id', p_position_id)
  );
  RETURN v_new_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_vacancy_request(uuid,uuid,uuid,text,integer,date,text,uuid,boolean,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.submit_vacancy_for_approval(p_vacancy_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id uuid := public.get_my_profile_id();
  v_role       text := public.get_my_role();
  v            public.vacancies;
BEGIN
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vacancy not found: %', p_vacancy_id; END IF;

  IF NOT (public.i_have_full_access() OR public.i_have_account_scope(v.account_id)) THEN
    RAISE EXCEPTION 'Vacancy % is outside your scope', p_vacancy_id USING ERRCODE='42501';
  END IF;

  IF v.status <> 'Draft' THEN
    RAISE EXCEPTION 'Only Draft vacancies can be submitted (current: %)', v.status
      USING ERRCODE='check_violation';
  END IF;

  UPDATE public.vacancies
     SET status = 'Pending Approval', updated_by = v_profile_id, updated_at = now()
   WHERE id = p_vacancy_id;

  PERFORM public.log_audit_event(
    'vacancies','UPDATE', p_vacancy_id,
    jsonb_build_object('status', v.status),
    jsonb_build_object('status','Pending Approval','semantic_action','SUBMIT_FOR_APPROVAL','actor_role', v_role)
  );
  RETURN jsonb_build_object('id', p_vacancy_id, 'status', 'Pending Approval');
END;
$$;
GRANT EXECUTE ON FUNCTION public.submit_vacancy_for_approval(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.approve_vacancy_request(p_vacancy_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id uuid := public.get_my_profile_id();
  v_role       text := public.get_my_role();
  v            public.vacancies;
BEGIN
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'Only Super Admin or Head Admin can approve vacancies' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vacancy not found: %', p_vacancy_id; END IF;

  -- Head Admin scope-check (if user_scopes entries exist for this HA)
  IF v_role = 'Head Admin'
     AND EXISTS (SELECT 1 FROM public.user_scopes WHERE user_id = v_profile_id)
     AND NOT public.i_have_account_scope(v.account_id) THEN
    RAISE EXCEPTION 'Vacancy % is outside your assigned scope', p_vacancy_id USING ERRCODE='42501';
  END IF;

  IF v.status <> 'Pending Approval' THEN
    RAISE EXCEPTION 'Only Pending Approval vacancies can be approved (current: %)', v.status
      USING ERRCODE='check_violation';
  END IF;

  UPDATE public.vacancies
     SET status = 'Open', updated_by = v_profile_id, updated_at = now()
   WHERE id = p_vacancy_id;

  PERFORM public.log_audit_event(
    'vacancies','APPROVAL', p_vacancy_id,
    jsonb_build_object('status', v.status),
    jsonb_build_object('status','Open','semantic_action','APPROVE_VACANCY','actor_role', v_role)
  );
  RETURN jsonb_build_object('id', p_vacancy_id, 'status', 'Open');
END;
$$;
GRANT EXECUTE ON FUNCTION public.approve_vacancy_request(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.reject_vacancy_request(p_vacancy_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id uuid := public.get_my_profile_id();
  v_role       text := public.get_my_role();
  v            public.vacancies;
BEGIN
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'Only Super Admin or Head Admin can reject vacancies' USING ERRCODE='42501';
  END IF;
  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'Rejection reason is required';
  END IF;

  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vacancy not found: %', p_vacancy_id; END IF;

  IF v_role = 'Head Admin'
     AND EXISTS (SELECT 1 FROM public.user_scopes WHERE user_id = v_profile_id)
     AND NOT public.i_have_account_scope(v.account_id) THEN
    RAISE EXCEPTION 'Vacancy % is outside your assigned scope', p_vacancy_id USING ERRCODE='42501';
  END IF;

  IF v.status NOT IN ('Pending Approval','Draft') THEN
    RAISE EXCEPTION 'Cannot reject vacancy in status %', v.status USING ERRCODE='check_violation';
  END IF;

  UPDATE public.vacancies
     SET status = 'Rejected',
         remarks = COALESCE(remarks,'') ||
                   CASE WHEN remarks IS NULL OR remarks='' THEN '' ELSE E'\n' END ||
                   '[REJECTED] ' || p_reason,
         updated_by = v_profile_id, updated_at = now()
   WHERE id = p_vacancy_id;

  PERFORM public.log_audit_event(
    'vacancies','UPDATE', p_vacancy_id,
    jsonb_build_object('status', v.status),
    jsonb_build_object('status','Rejected','semantic_action','REJECT_VACANCY','reason', p_reason,'actor_role', v_role)
  );
  RETURN jsonb_build_object('id', p_vacancy_id, 'status', 'Rejected');
END;
$$;
GRANT EXECUTE ON FUNCTION public.reject_vacancy_request(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.close_vacancy_request(p_vacancy_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id uuid := public.get_my_profile_id();
  v_role       text := public.get_my_role();
  v            public.vacancies;
BEGIN
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'Closure reason is required';
  END IF;

  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vacancy not found: %', p_vacancy_id; END IF;

  -- Scope: SA/HA always; Encoder/HRCO/OM in account scope
  IF NOT (public.i_have_full_access() OR public.i_have_account_scope(v.account_id)) THEN
    RAISE EXCEPTION 'Vacancy % is outside your scope', p_vacancy_id USING ERRCODE='42501';
  END IF;

  -- Transition guard (validator handles it too, but give a clearer error here)
  IF v.status NOT IN ('Draft','Pending Approval','Open','On Hold') THEN
    RAISE EXCEPTION 'Cannot close vacancy in status %', v.status USING ERRCODE='check_violation';
  END IF;

  UPDATE public.vacancies
     SET status = 'Closed',
         closure_request_status = 'Approved',
         has_pending_closure = false,
         remarks = COALESCE(remarks,'') ||
                   CASE WHEN remarks IS NULL OR remarks='' THEN '' ELSE E'\n' END ||
                   '[CLOSED] ' || p_reason,
         updated_by = v_profile_id, updated_at = now()
   WHERE id = p_vacancy_id;

  PERFORM public.log_audit_event(
    'vacancies','UPDATE', p_vacancy_id,
    jsonb_build_object('status', v.status),
    jsonb_build_object('status','Closed','semantic_action','CLOSE_VACANCY','reason', p_reason,'actor_role', v_role)
  );
  RETURN jsonb_build_object('id', p_vacancy_id, 'status','Closed');
END;
$$;
GRANT EXECUTE ON FUNCTION public.close_vacancy_request(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.assign_applicant_to_vacancy(p_vacancy_id uuid, p_applicant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id uuid := public.get_my_profile_id();
  v_role       text := public.get_my_role();
  v_role_lvl   int  := public.get_my_role_level();
  v            public.vacancies;
  v_app        public.applicants;
BEGIN
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;

  -- Recruitment / Encoder / HRCO / OM / SA / HA may assign
  IF v_role_lvl < 20 OR v_role = 'Viewer' OR v_role = 'Back Office' THEN
    RAISE EXCEPTION 'Role % cannot assign applicants', v_role USING ERRCODE='42501';
  END IF;

  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vacancy not found: %', p_vacancy_id; END IF;
  IF v.status <> 'Open' THEN
    RAISE EXCEPTION 'Can only assign applicants to Open vacancies (current: %)', v.status
      USING ERRCODE='check_violation';
  END IF;
  IF NOT (public.i_have_full_access() OR public.i_have_account_scope(v.account_id)) THEN
    RAISE EXCEPTION 'Vacancy outside your scope' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Applicant not found: %', p_applicant_id; END IF;

  UPDATE public.applicants
     SET vacancy_vcode = v.vcode,
         updated_by    = v_profile_id,
         updated_at    = now()
   WHERE id = p_applicant_id;

  PERFORM public.log_audit_event(
    'applicants','UPDATE', p_applicant_id,
    to_jsonb(v_app),
    jsonb_build_object('vacancy_vcode', v.vcode, 'vacancy_id', v.id,
                       'semantic_action','ASSIGN_APPLICANT_TO_VACANCY', 'actor_role', v_role)
  );
  RETURN jsonb_build_object('vacancy_id', v.id, 'applicant_id', p_applicant_id, 'vacancy_vcode', v.vcode);
END;
$$;
GRANT EXECUTE ON FUNCTION public.assign_applicant_to_vacancy(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_vacancy_filled(p_vacancy_id uuid, p_applicant_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id uuid := public.get_my_profile_id();
  v_role       text := public.get_my_role();
  v_role_lvl   int  := public.get_my_role_level();
  v            public.vacancies;
  v_app        public.applicants;
BEGIN
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  -- Encoder, HRCO, OM, SA, HA can mark filled
  IF v_role NOT IN ('Super Admin','Head Admin','Encoder','HRCO','Operations Manager') THEN
    RAISE EXCEPTION 'Role % cannot mark vacancy filled', v_role USING ERRCODE='42501';
  END IF;

  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vacancy not found: %', p_vacancy_id; END IF;
  IF NOT (public.i_have_full_access() OR public.i_have_account_scope(v.account_id)) THEN
    RAISE EXCEPTION 'Vacancy outside your scope' USING ERRCODE='42501';
  END IF;
  IF v.status <> 'Open' THEN
    RAISE EXCEPTION 'Only Open vacancies can be marked Filled (current: %)', v.status
      USING ERRCODE='check_violation';
  END IF;

  IF p_applicant_id IS NOT NULL THEN
    SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Applicant not found: %', p_applicant_id; END IF;
    IF v_app.vacancy_vcode IS DISTINCT FROM v.vcode THEN
      RAISE EXCEPTION 'Applicant % is not assigned to vacancy %', p_applicant_id, p_vacancy_id;
    END IF;
    UPDATE public.applicants
       SET status='Hired', hired_date = COALESCE(hired_date, CURRENT_DATE),
           hired_at = COALESCE(hired_at, now()),
           deployed_by_user_id = v_profile_id,
           updated_by = v_profile_id, updated_at = now()
     WHERE id = p_applicant_id;
  END IF;

  UPDATE public.vacancies
     SET status='Filled', updated_by = v_profile_id, updated_at = now()
   WHERE id = p_vacancy_id;

  PERFORM public.log_audit_event(
    'vacancies','APPROVAL', p_vacancy_id,
    jsonb_build_object('status', v.status),
    jsonb_build_object('status','Filled','semantic_action','MARK_VACANCY_FILLED',
                       'applicant_id', p_applicant_id, 'actor_role', v_role)
  );
  RETURN jsonb_build_object('id', p_vacancy_id, 'status','Filled', 'applicant_id', p_applicant_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.mark_vacancy_filled(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_vacancies(
  p_status_filter text DEFAULT NULL,
  p_limit         integer DEFAULT 200,
  p_offset        integer DEFAULT 0
)
RETURNS TABLE (vacancy jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role        text := public.get_my_role();
  v_profile_id  uuid := public.get_my_profile_id();
  v_full_access bool := public.i_have_full_access();
BEGIN
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;

  RETURN QUERY
  SELECT public.fn_mask_vacancy_for_role(v.*, v_role)
  FROM public.vacancies v
  WHERE COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND (
      v_full_access
      OR v.account_id = ANY (public.get_my_allowed_account_ids())
      OR (v_role IN ('HRCO','Recruitment Team','Encoder')
          AND (v.hrco_user_id = v_profile_id
               OR v.assigned_encoder_id = v_profile_id
               OR v.requested_by_user_id = v_profile_id))
    )
    AND (p_status_filter IS NULL OR v.status = p_status_filter)
  ORDER BY v.created_at DESC
  LIMIT GREATEST(p_limit, 0) OFFSET GREATEST(p_offset, 0);
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_my_vacancies(text,integer,integer) TO authenticated;

COMMIT;
