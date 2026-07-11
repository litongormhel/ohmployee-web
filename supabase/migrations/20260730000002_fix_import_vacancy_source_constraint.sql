-- ============================================================
-- OHM2026_1137 — Fix Import Vacancy source constraint failure
-- Migration: 20260730000002_fix_import_vacancy_source_constraint.sql
-- Depends on: 20260730000001_fix_import_vacancy_audit_action_enum.sql
-- ============================================================
-- Problem
--   approve_vacancy_import inserts into vacancies with source='migration',
--   which is not in the vacancies_source_check constraint:
--     source IN ('hc_request', 'plantilla', 'manual')
--
--   Result: COMMIT_FAILED: new row for relation "vacancies" violates
--   check constraint "vacancies_source_check"
--
-- Fix
--   Replace approve_vacancy_import so inserted rows use source='manual'.
--   source_vacancy_import_batch_id is preserved for migration provenance.
--   vacancies_source_check is NOT altered or weakened.
--   No new source value is added.
-- ============================================================


CREATE OR REPLACE FUNCTION public.approve_vacancy_import(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid        uuid := auth.uid();
  v_actor      uuid := public.get_current_profile_id();
  v_batch      public.vacancy_import_batches%ROWTYPE;
  v_acct_name  text;
  v_grp_name   text;

  v_r          record;
  v_vac_id     uuid;
  v_vac_done   int := 0;
  v_app_done   int := 0;
  v_app_name   text;
BEGIN
  -- ── Auth ─────────────────────────────────────────────────────────────────
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.vacancy_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  SELECT account_name INTO v_acct_name
    FROM public.accounts WHERE id = v_batch.selected_account_id;
  SELECT group_name INTO v_grp_name
    FROM public.groups WHERE id = v_batch.selected_group_id;

  -- ── Commit rows ───────────────────────────────────────────────────────────
  FOR v_r IN
    SELECT *
      FROM public.vacancy_import_rows
     WHERE batch_id = p_batch_id
       AND validation_status IN ('valid','flagged')
       AND vcode IS NOT NULL
     ORDER BY row_number
  LOOP
    -- Defence-in-depth: never duplicate an existing official VCODE.
    IF EXISTS (
      SELECT 1 FROM public.vacancies vv
      WHERE upper(vv.vcode) = upper(v_r.vcode)
        AND COALESCE(vv.is_archived, false) = false
        AND vv.deleted_at IS NULL
    ) THEN
      CONTINUE;
    END IF;

    INSERT INTO public.vacancies (
      vcode, account, position, status,
      account_id, group_id,
      chain, province, store_name, area_city,
      employment_type, request_type, vacancy_type,
      vacant_date, target_fill_date,
      required_headcount, has_penalty,
      hrco_name, hrco_mobile,
      source, source_vacancy_import_batch_id,
      created_by, created_by_user_id, is_archived, has_pending_closure
    ) VALUES (
      v_r.vcode, v_acct_name, v_r.position, 'Open',
      v_batch.selected_account_id, v_batch.selected_group_id,
      v_r.chain, v_r.province, v_r.store_name, v_r.city,
      v_r.employment_type, v_r.request_type_norm,
      CASE WHEN v_r.request_type_norm = 'Replacement' THEN 'Replacement' ELSE 'New' END,
      v_r.vacant_date_raw::date,
      NULLIF(v_r.target_fill_date_raw,'')::date,
      COALESCE(v_r.hc_raw::int, 1), COALESCE(v_r.with_penalty_norm, false),
      v_r.hrco, v_r.contact_number,
      'manual', p_batch_id,
      v_actor, v_actor, false, false
    ) RETURNING id INTO v_vac_id;
    v_vac_done := v_vac_done + 1;

    -- Pipeline rows seed one applicant (presence of applicant ⇒ Pipeline tab)
    IF v_r.derived_tab = 'pipeline' THEN
      v_app_name := trim(
        COALESCE(v_r.applicant_last_name,'') ||
        CASE WHEN v_r.applicant_first_name IS NOT NULL
             THEN ', ' || v_r.applicant_first_name ELSE '' END ||
        CASE WHEN v_r.applicant_middle_name IS NOT NULL
             THEN ' ' || v_r.applicant_middle_name ELSE '' END);
      IF v_app_name = '' OR v_app_name = ',' THEN
        v_app_name := COALESCE(v_r.applicant_first_name, v_r.applicant_last_name, 'Applicant');
      END IF;

      INSERT INTO public.applicants (
        vacancy_vcode, full_name, full_name_snapshot,
        last_name, first_name, middle_name,
        contact_number, status, created_by, updated_by
      ) VALUES (
        v_r.vcode, v_app_name, v_app_name,
        v_r.applicant_last_name, v_r.applicant_first_name, v_r.applicant_middle_name,
        v_r.contact_number, COALESCE(v_r.applicant_status, 'New'),
        v_actor, v_actor
      );
      v_app_done := v_app_done + 1;
    END IF;
  END LOOP;

  -- ── Finalise batch ────────────────────────────────────────────────────────
  UPDATE public.vacancy_import_batches
     SET status               = 'approved',
         approved_by          = v_uid,
         approved_at          = now(),
         committed_vacancies  = v_vac_done,
         committed_applicants = v_app_done,
         updated_at           = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'APPROVAL', p_batch_id,
    jsonb_build_object(
      'vacancies',  v_vac_done,
      'applicants', v_app_done,
      'group',      v_grp_name,
      'account',    v_acct_name
    ));

  RETURN jsonb_build_object(
    'batch_id',             p_batch_id,
    'status',               'approved',
    'vacancies_committed',  v_vac_done,
    'applicants_committed', v_app_done
  );
EXCEPTION WHEN others THEN
  -- Commit failure: record the error on the batch and re-raise.
  UPDATE public.vacancy_import_batches
     SET status              = 'commit_failed',
         commit_error_detail = SQLERRM,
         updated_at          = now()
   WHERE id = p_batch_id;
  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object('event', 'commit_failed', 'error', SQLERRM));
  RAISE EXCEPTION 'COMMIT_FAILED: %', SQLERRM USING ERRCODE = '22000';
END$func$;

REVOKE ALL ON FUNCTION public.approve_vacancy_import(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_vacancy_import(uuid) TO authenticated;

COMMENT ON FUNCTION public.approve_vacancy_import IS
  'Commit RPC for the one-time Import Vacancy migration (OHM2026_1135). '
  'Inserts vacancies preserving VCODEs; pipeline rows seed one applicant. '
  'source=''manual'' (satisfies vacancies_source_check); migration provenance '
  'is retained via source_vacancy_import_batch_id (OHM2026_1137). '
  'Records commit failures on the batch. RBAC: Head Admin / Super Admin only. '
  'OHM2026_1136: commit-failure audit log uses UPDATE (COMMIT_FAILED was invalid).';
