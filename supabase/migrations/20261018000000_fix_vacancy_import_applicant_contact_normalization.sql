-- ============================================================
-- OHM2026_0087
-- Fix Vacancy Import applicant contact normalization at commit.
--
-- Root cause:
--   Review Import can allow Pipeline applicant rows with a blank contact, but
--   approve_vacancy_import inserted the raw empty string into applicants.
--   That violated chk_applicants_contact_number_format at commit time.
--
-- Fix:
--   * Preflight all committable Pipeline rows before any insert/restore DML.
--   * Trim and remove non-digit formatting from applicant contact values.
--   * Store blank applicant contacts as NULL.
--   * Store 10-digit PH mobile values as 0 + digits so the existing DB
--     constraint remains unchanged.
--   * Reject invalid non-empty contacts with the import row number before
--     applicant insert, avoiding raw COMMIT_FAILED constraint errors.
--
-- Validation SQL checklist:
--   1. Pipeline contact 9123456789 approves and stores 09123456789.
--   2. Pipeline contact 09123556789 approves and stores 09123556789.
--   3. Blank Pipeline contact approves and stores NULL.
--   4. 9 digits raises:
--        Invalid applicant contact number on row <n>. Use 10 digits starting
--        with 9 or 11 digits starting with 09.
--   5. 12 digits raises the same row-level message before insert.
--   6. No chk_applicants_contact_number_format / raw COMMIT_FAILED message
--      appears for these applicant-contact cases.
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

  v_r              record;
  v_existing       record;
  v_vac_id         uuid;
  v_vac_done       int := 0;
  v_vac_restored   int := 0;
  v_app_done       int := 0;
  v_app_name       text;
  v_app_contact    text;
BEGIN
  -- Auth
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

  -- Preflight applicant contact values before any commit DML.
  FOR v_r IN
    SELECT row_number, contact_number
      FROM public.vacancy_import_rows
     WHERE batch_id = p_batch_id
       AND validation_status IN ('valid','flagged')
       AND vcode IS NOT NULL
       AND derived_tab = 'pipeline'
     ORDER BY row_number
  LOOP
    v_app_contact := regexp_replace(btrim(COALESCE(v_r.contact_number, '')), '[^0-9]', '', 'g');

    IF v_app_contact <> ''
       AND NOT (
         v_app_contact ~ '^9[0-9]{9}$'
         OR v_app_contact ~ '^09[0-9]{9}$'
       ) THEN
      RAISE EXCEPTION
        'VACANCY_IMPORT_CONTACT_INVALID: Invalid applicant contact number on row %. Use 10 digits starting with 9 or 11 digits starting with 09.',
        v_r.row_number
        USING ERRCODE = '22023';
    END IF;
  END LOOP;

  -- Commit rows
  FOR v_r IN
    SELECT *
      FROM public.vacancy_import_rows
     WHERE batch_id = p_batch_id
       AND validation_status IN ('valid','flagged')
       AND vcode IS NOT NULL
     ORDER BY row_number
  LOOP
    -- Defence-in-depth: never duplicate an existing ACTIVE official VCODE.
    IF EXISTS (
      SELECT 1 FROM public.vacancies vv
      WHERE upper(vv.vcode) = upper(v_r.vcode)
        AND COALESCE(vv.is_archived, false) = false
        AND vv.deleted_at IS NULL
    ) THEN
      CONTINUE;
    END IF;

    -- Restore-or-insert: if a soft-deleted Import-Vacancy row exists for
    -- this VCODE, restore it in place. This avoids colliding with the
    -- unconditional UNIQUE(vcode) constraint (`vacancies_vcode_key`)
    -- which is still referenced by FKs from applicants, plantilla,
    -- vacancy_closure_requests, employee_deployments, and hr_emploc.
    --
    -- We ONLY restore rows that carry a non-null
    -- `source_vacancy_import_batch_id` - i.e. rows originally created
    -- by a previous Import Vacancy batch. Soft-deleted vacancies from
    -- any other origin must still block to preserve historical intent.
    SELECT id
      INTO v_existing
      FROM public.vacancies vv
     WHERE upper(vv.vcode) = upper(v_r.vcode)
       AND vv.deleted_at IS NOT NULL
       AND vv.source_vacancy_import_batch_id IS NOT NULL
     ORDER BY vv.deleted_at DESC NULLS LAST
     LIMIT 1
     FOR UPDATE;

    IF FOUND THEN
      -- Restore + refresh fields from the new import row, and re-point
      -- provenance to the new batch.
      UPDATE public.vacancies
         SET deleted_at                     = NULL,
             is_archived                    = false,
             status                         = 'Open',
             has_pending_closure            = false,
             account                        = v_acct_name,
             account_id                     = v_batch.selected_account_id,
             group_id                       = v_batch.selected_group_id,
             position                       = v_r.position,
             chain                          = v_r.chain,
             province                       = v_r.province,
             store_name                     = v_r.store_name,
             area_city                      = v_r.city,
             employment_type                = v_r.employment_type,
             request_type                   = v_r.request_type_norm,
             vacancy_type                   = CASE
                                                WHEN v_r.request_type_norm = 'Replacement'
                                                THEN 'Replacement'
                                                ELSE 'New'
                                             END,
             vacant_date                    = v_r.vacant_date_raw::date,
             target_fill_date               = NULLIF(v_r.target_fill_date_raw,'')::date,
             required_headcount             = COALESCE(v_r.hc_raw::int, 1),
             has_penalty                    = COALESCE(v_r.with_penalty_norm, false),
             hrco_name                      = v_r.hrco,
             hrco_mobile                    = v_r.contact_number,
             source                         = 'manual',
             source_vacancy_import_batch_id = p_batch_id,
             updated_by                     = v_actor
       WHERE id = v_existing.id
       RETURNING id INTO v_vac_id;

      v_vac_restored := v_vac_restored + 1;
    ELSE
      -- Fresh insert (no prior import-vacancy soft-deleted row for this VCODE).
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
    END IF;

    v_vac_done := v_vac_done + 1;

    -- Pipeline rows seed one applicant (presence of applicant => Pipeline tab)
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

      v_app_contact := regexp_replace(btrim(COALESCE(v_r.contact_number, '')), '[^0-9]', '', 'g');
      v_app_contact := CASE
                         WHEN v_app_contact = '' THEN NULL
                         WHEN v_app_contact ~ '^9[0-9]{9}$' THEN '0' || v_app_contact
                         ELSE v_app_contact
                       END;

      INSERT INTO public.applicants (
        vacancy_vcode, full_name, full_name_snapshot,
        last_name, first_name, middle_name,
        contact_number, status, created_by, updated_by
      ) VALUES (
        v_r.vcode, v_app_name, v_app_name,
        v_r.applicant_last_name, v_r.applicant_first_name, v_r.applicant_middle_name,
        v_app_contact, COALESCE(v_r.applicant_status, 'New'),
        v_actor, v_actor
      );
      v_app_done := v_app_done + 1;
    END IF;
  END LOOP;

  -- Finalise batch
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
      'vacancies',           v_vac_done,
      'vacancies_restored',  v_vac_restored,
      'applicants',          v_app_done,
      'group',               v_grp_name,
      'account',             v_acct_name
    ));

  RETURN jsonb_build_object(
    'batch_id',             p_batch_id,
    'status',               'approved',
    'vacancies_committed',  v_vac_done,
    'vacancies_restored',   v_vac_restored,
    'applicants_committed', v_app_done
  );
EXCEPTION WHEN others THEN
  IF SQLSTATE = '22023'
     AND SQLERRM LIKE 'VACANCY_IMPORT_CONTACT_INVALID:%' THEN
    RAISE EXCEPTION '%', replace(SQLERRM, 'VACANCY_IMPORT_CONTACT_INVALID: ', '')
      USING ERRCODE = '22023';
  END IF;

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
  'OHM2026_1142B: when re-importing a VCODE whose previous Import Vacancy '
  'row was rolled back (soft-deleted, source_vacancy_import_batch_id IS NOT NULL), '
  'the existing row is restored in place instead of inserting a new row. '
  'OHM2026_0087: applicant contacts are normalized before insert; blank contacts '
  'store as NULL, 10-digit 9XXXXXXXXX values store as 09XXXXXXXXX, and invalid '
  'non-empty contacts fail with a row-level message before insert.';
