-- ============================================================
-- OHM2026_0065 — Three targeted fixes
--
-- SS1  Import Vacancy approval failure (duplicate key on vacancies_vcode_key)
--   Root cause: submit_vacancy_import only blocked VCODEs with
--   ACTIVE (non-archived, not deleted) vacancy rows.  Soft-deleted
--   non-import rows (deleted_at IS NOT NULL AND
--   source_vacancy_import_batch_id IS NULL) were not detected at
--   dry-run time.  They cannot be restored by approve_vacancy_import
--   (the restore path requires source_vacancy_import_batch_id IS NOT
--   NULL), so the subsequent INSERT hit the unconditional
--   vacancies_vcode_key UNIQUE constraint and the batch landed in
--   commit_failed.
--
--   Fix: widen the VCODE-existence check in submit_vacancy_import to
--   block ANY row that is not a soft-deleted IMPORT vacancy
--   (i.e. NOT (deleted_at IS NOT NULL AND
--              source_vacancy_import_batch_id IS NOT NULL)).
--   Soft-deleted import rows are still allowed through because
--   approve_vacancy_import will restore them in place.
--
-- SS2  Create VCODE rollback — Flutter only (no SQL change)
--   PostgrestException is now caught explicitly in
--   HeadcountRequestDetailScreen._generateVcode so the backend
--   error is surfaced to the user instead of the generic
--   "An unexpected error occurred."
--   The backend create_plantilla_slot_from_request already rolls
--   back automatically via PL/pgSQL implicit transaction semantics.
--
-- SS3  Plantilla import roving employment type
--   Root cause: approve_plantilla_import_batch trusted the XLSX
--   EMPLOYMENT_TYPE column to set deployment_type.  Employees who
--   appear in multiple VCODEs within the same batch
--   (v_store_cnt > 1) are always Roving by structural definition;
--   their XLSX column may incorrectly say "Stationary".
--
--   Fix: after normalising v_deployment_type from the XLSX value,
--   override it to 'Roving' when v_store_cnt > 1.  The UI displays
--   the backend-computed value only; the XLSX value is not trusted.
--
-- RPCs touched:
--   public.submit_vacancy_import(text,uuid,uuid,jsonb)        — SS1
--   public.approve_plantilla_import_batch(uuid)               — SS3
--
-- Depends on:
--   20260731000001_import_vacancy_cross_account_applicant_precheck.sql
--   20260803000000_fix_plantilla_import_profile_field_hydration.sql
--
-- Replay safety: CREATE OR REPLACE on both functions — idempotent.
-- No DDL (tables/columns/constraints) is changed.
-- ============================================================


-- ============================================================
-- §1  SS1 — Fix VCODE existence check in submit_vacancy_import
-- ============================================================
-- Full replacement of submit_vacancy_import.
-- Only change vs 20260731000001: the VCODE-already-in-vacancies
-- check is widened from "active only" to "any non-restorable row".
-- All other logic (cross-account precheck, OHM2026_1151 approval
-- gating, OHM2026_1150 enriched conflict messages) is preserved
-- verbatim.
-- ============================================================

CREATE OR REPLACE FUNCTION public.submit_vacancy_import(
  p_file_name  text,
  p_group_id   uuid,
  p_account_id uuid,
  p_rows       jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid         uuid := auth.uid();
  v_role        text := public.get_my_role();
  v_batch_id    uuid;
  v_acct_group  uuid;
  v_acct_name   text;
  v_group_name  text;

  v_row         jsonb;
  v_idx         int := 0;

  -- Parsed CSV fields
  v_vcode       text;
  v_csv_group   text;
  v_chain       text;
  v_csv_acct    text;
  v_store_nm    text;
  v_position    text;
  v_hc_raw      text;
  v_emp_type    text;
  v_req_raw     text;
  v_req_norm    text;
  v_vacant_raw  text;
  v_vacant_dt   date;
  v_prov        text;
  v_city        text;
  v_tfd_raw     text;
  v_hrco        text;
  v_contact     text;
  v_pen_raw     text;
  v_pen_norm    boolean;
  v_app_last    text;
  v_app_first   text;
  v_app_mid     text;
  v_app_status  text;
  v_app_source  text;
  v_mig_source  text;
  v_mig_notes   text;

  -- Per-row state
  v_errs        jsonb;
  v_flags       jsonb;
  v_status      text;
  v_tab         text;
  v_is_existing boolean;
  v_has_app     boolean;

  -- Cross-account applicant precheck (OHM2026_1150 + OHM2026_1151)
  v_conflict_acct    text;
  v_conflict_grp     text;
  v_conflict_status  text;

  -- Batch counters
  v_total       int := 0;
  v_valid       int := 0;
  v_flagged     int := 0;
  v_skipped     int := 0;
  v_blocked     int := 0;
  v_open        int := 0;
  v_pipeline    int := 0;
  v_dup_vcode   int := 0;
  v_exist_vcode int := 0;
  v_ctx_mismatch int := 0;
  v_cross_acct  int := 0;

  v_summary     jsonb;
  v_final       text;
BEGIN
  -- ── Auth ─────────────────────────────────────────────────────────────────
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Input validation ─────────────────────────────────────────────────────
  IF p_file_name IS NULL OR length(trim(p_file_name)) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: file_name required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_rows must be a jsonb array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_rows) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_rows is empty' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_rows) > 5000 THEN
    RAISE EXCEPTION 'INVALID_INPUT: max 5000 rows per batch' USING ERRCODE = '22023';
  END IF;

  -- ── Scope validation ─────────────────────────────────────────────────────
  SELECT group_name INTO v_group_name FROM public.groups WHERE id = p_group_id;
  IF v_group_name IS NULL THEN
    RAISE EXCEPTION 'INVALID_GROUP: %', p_group_id USING ERRCODE = '23503';
  END IF;
  SELECT group_id, account_name INTO v_acct_group, v_acct_name
    FROM public.accounts WHERE id = p_account_id;
  IF v_acct_group IS NULL THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: %', p_account_id USING ERRCODE = '23503';
  END IF;
  IF v_acct_group <> p_group_id THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: account % does not belong to group %',
      p_account_id, p_group_id USING ERRCODE = '23503';
  END IF;
  IF NOT public.i_have_full_access()
     AND NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: target account is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  -- ── Create batch ─────────────────────────────────────────────────────────
  INSERT INTO public.vacancy_import_batches (
    file_name, uploaded_by, uploaded_role,
    selected_group_id, selected_account_id, status
  ) VALUES (
    p_file_name, v_uid, v_role, p_group_id, p_account_id, 'draft_uploaded'
  ) RETURNING id INTO v_batch_id;

  -- ── Pre-pass: VCODEs duplicated within this upload ────────────────────────
  DROP TABLE IF EXISTS _vib_dup_vcodes;
  CREATE TEMP TABLE _vib_dup_vcodes ON COMMIT DROP AS
  SELECT upper(trim(elem->>'VCODE')) AS vcode
  FROM jsonb_array_elements(p_rows) elem
  WHERE NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
  GROUP BY 1 HAVING count(*) > 1;

  -- ── Row loop ─────────────────────────────────────────────────────────────
  FOR v_row IN SELECT elem.value FROM jsonb_array_elements(p_rows) AS elem(value)
  LOOP
    v_idx         := v_idx + 1;
    v_total       := v_total + 1;
    v_errs        := '[]'::jsonb;
    v_flags       := '[]'::jsonb;
    v_is_existing := false;
    v_req_norm    := NULL;
    v_vacant_dt   := NULL;
    v_pen_norm    := false;
    v_conflict_acct   := NULL;
    v_conflict_grp    := NULL;
    v_conflict_status := NULL;

    -- Parse CSV fields
    v_vcode      := upper(NULLIF(trim(COALESCE(v_row->>'VCODE','')), ''));
    v_csv_group  := NULLIF(trim(COALESCE(v_row->>'GROUP_NAME','')), '');
    v_chain      := NULLIF(trim(COALESCE(v_row->>'CHAIN','')), '');
    v_csv_acct   := NULLIF(trim(COALESCE(v_row->>'ACCOUNT_NAME','')), '');
    v_store_nm   := NULLIF(trim(COALESCE(v_row->>'STORE_NAME','')), '');
    v_position   := NULLIF(trim(COALESCE(v_row->>'POSITION','')), '');
    v_hc_raw     := NULLIF(trim(COALESCE(v_row->>'HC','')), '');
    v_emp_type   := NULLIF(trim(COALESCE(v_row->>'EMPLOYMENT_TYPE','')), '');
    v_req_raw    := NULLIF(trim(COALESCE(v_row->>'REQUEST_TYPE','')), '');
    v_vacant_raw := NULLIF(trim(COALESCE(v_row->>'VACANT_DATE','')), '');
    v_prov       := NULLIF(trim(COALESCE(v_row->>'PROVINCE','')), '');
    v_city       := NULLIF(trim(COALESCE(v_row->>'CITY','')), '');
    v_tfd_raw    := NULLIF(trim(COALESCE(v_row->>'TARGET_FILL_DATE','')), '');
    v_hrco       := NULLIF(trim(COALESCE(v_row->>'HRCO','')), '');
    v_contact    := NULLIF(trim(COALESCE(v_row->>'CONTACT_NUMBER','')), '');
    v_pen_raw    := NULLIF(trim(COALESCE(v_row->>'WITH_PENALTY','')), '');
    v_app_last   := NULLIF(trim(COALESCE(v_row->>'APPLICANT_LAST_NAME','')), '');
    v_app_first  := NULLIF(trim(COALESCE(v_row->>'APPLICANT_FIRST_NAME','')), '');
    v_app_mid    := NULLIF(trim(COALESCE(v_row->>'APPLICANT_MIDDLE_NAME','')), '');
    v_app_status := NULLIF(trim(COALESCE(v_row->>'APPLICANT_STATUS','')), '');
    v_app_source := NULLIF(trim(COALESCE(v_row->>'APPLICANT_SOURCE','')), '');
    v_mig_source := NULLIF(trim(COALESCE(v_row->>'MIGRATION_SOURCE','')), '');
    v_mig_notes  := NULLIF(trim(COALESCE(v_row->>'MIGRATION_NOTES','')), '');

    -- Required field checks (blocking)
    IF v_vcode    IS NULL THEN v_errs := v_errs || '[{"field":"VCODE","msg":"required"}]'::jsonb; END IF;
    IF v_csv_group IS NULL THEN v_errs := v_errs || '[{"field":"GROUP_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_chain    IS NULL THEN v_errs := v_errs || '[{"field":"CHAIN","msg":"required"}]'::jsonb; END IF;
    IF v_csv_acct IS NULL THEN v_errs := v_errs || '[{"field":"ACCOUNT_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_store_nm IS NULL THEN v_errs := v_errs || '[{"field":"STORE_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_position IS NULL THEN v_errs := v_errs || '[{"field":"POSITION","msg":"required"}]'::jsonb; END IF;
    IF v_hc_raw   IS NULL THEN v_errs := v_errs || '[{"field":"HC","msg":"required"}]'::jsonb; END IF;
    IF v_emp_type IS NULL THEN v_errs := v_errs || '[{"field":"EMPLOYMENT_TYPE","msg":"required"}]'::jsonb; END IF;
    IF v_req_raw  IS NULL THEN v_errs := v_errs || '[{"field":"REQUEST_TYPE","msg":"required"}]'::jsonb; END IF;
    IF v_vacant_raw IS NULL THEN v_errs := v_errs || '[{"field":"VACANT_DATE","msg":"required"}]'::jsonb; END IF;
    IF v_prov     IS NULL THEN v_errs := v_errs || '[{"field":"PROVINCE","msg":"required"}]'::jsonb; END IF;
    IF v_city     IS NULL THEN v_errs := v_errs || '[{"field":"CITY","msg":"required"}]'::jsonb; END IF;

    -- Group / account context match vs UI selection
    IF v_csv_group IS NOT NULL AND lower(v_csv_group) <> lower(v_group_name) THEN
      v_errs := v_errs || jsonb_build_array(jsonb_build_object(
        'field','GROUP_NAME',
        'msg', format('CSV group "%s" does not match selected group "%s"',
                      v_csv_group, v_group_name)));
      v_ctx_mismatch := v_ctx_mismatch + 1;
    END IF;
    IF v_csv_acct IS NOT NULL AND lower(v_csv_acct) <> lower(v_acct_name) THEN
      v_errs := v_errs || jsonb_build_array(jsonb_build_object(
        'field','ACCOUNT_NAME',
        'msg', format('CSV account "%s" does not match selected account "%s"',
                      v_csv_acct, v_acct_name)));
      v_ctx_mismatch := v_ctx_mismatch + 1;
    END IF;

    -- HC must equal exactly 1 (locked rule: 1 VCODE = 1 manpower slot).
    IF v_hc_raw IS NOT NULL THEN
      IF v_hc_raw !~ '^\d+$' OR v_hc_raw::int <> 1 THEN
        v_errs := v_errs || '[{"field":"HC","msg":"HC must be exactly 1 (1 VCODE = 1 manpower slot)"}]'::jsonb;
      END IF;
    END IF;

    -- REQUEST_TYPE normalisation + allowed-value check
    IF v_req_raw IS NOT NULL THEN
      v_req_norm := CASE lower(v_req_raw)
        WHEN 'replacement'         THEN 'Replacement'
        WHEN 'additional hc'       THEN 'Additional Headcount'
        WHEN 'additional headcount' THEN 'Additional Headcount'
        WHEN 'reliever'            THEN 'Reliever'
        WHEN 'commando'            THEN 'Commando'
        ELSE NULL
      END;
      IF v_req_norm IS NULL THEN
        v_errs := v_errs || jsonb_build_array(jsonb_build_object(
          'field','REQUEST_TYPE',
          'msg', format('"%s" is not allowed (Replacement, Additional HC, Reliever, Commando)',
                        v_req_raw)));
      END IF;
    END IF;

    -- VACANT_DATE must parse
    IF v_vacant_raw IS NOT NULL THEN
      BEGIN
        v_vacant_dt := v_vacant_raw::date;
      EXCEPTION WHEN others THEN
        v_vacant_dt := NULL;
        v_errs := v_errs || jsonb_build_array(jsonb_build_object(
          'field','VACANT_DATE',
          'msg', format('"%s" is not a valid date (use YYYY-MM-DD)', v_vacant_raw)));
      END;
    END IF;

    -- WITH_PENALTY normalisation (optional)
    IF v_pen_raw IS NOT NULL THEN
      v_pen_norm := CASE lower(v_pen_raw)
        WHEN 'yes' THEN true  WHEN 'y' THEN true
        WHEN 'true' THEN true WHEN '1' THEN true
        WHEN 'no' THEN false  WHEN 'n' THEN false
        WHEN 'false' THEN false WHEN '0' THEN false
        ELSE NULL
      END;
      IF v_pen_norm IS NULL THEN
        v_pen_norm := false;
        v_flags := v_flags || jsonb_build_array(jsonb_build_object(
          'flag','with_penalty_unrecognised',
          'msg', format('WITH_PENALTY "%s" not recognised — defaulted to No', v_pen_raw)));
      END IF;
    END IF;

    -- TARGET_FILL_DATE optional parse (flag only)
    IF v_tfd_raw IS NOT NULL THEN
      BEGIN
        PERFORM v_tfd_raw::date;
      EXCEPTION WHEN others THEN
        v_flags := v_flags || jsonb_build_array(jsonb_build_object(
          'flag','target_fill_date_invalid',
          'msg', format('TARGET_FILL_DATE "%s" ignored (unparseable)', v_tfd_raw)));
        v_tfd_raw := NULL;
      END;
    END IF;

    -- Duplicate VCODE within upload → block
    IF v_vcode IS NOT NULL AND EXISTS (SELECT 1 FROM _vib_dup_vcodes WHERE vcode = v_vcode) THEN
      v_errs := v_errs || '[{"field":"VCODE","msg":"duplicate VCODE in upload — each VCODE must appear exactly once"}]'::jsonb;
    END IF;

    -- ── OHM2026_0065 SS1 FIX ─────────────────────────────────────────────────
    -- VCODE already present in vacancies in any non-restorable form → block.
    --
    -- "Restorable" means a soft-deleted row that originated from a previous
    -- Import Vacancy batch (deleted_at IS NOT NULL AND
    -- source_vacancy_import_batch_id IS NOT NULL).  approve_vacancy_import
    -- restores those rows in place and does NOT insert a new row, so they
    -- do not collide with vacancies_vcode_key.
    --
    -- Every other existing row — active, archived, soft-deleted non-import —
    -- CANNOT be handled safely at commit time and MUST be blocked here.
    -- Allowing them through caused "duplicate key value violates unique
    -- constraint vacancies_vcode_key" at approval time.
    -- ─────────────────────────────────────────────────────────────────────────
    IF v_vcode IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.vacancies vv
      WHERE upper(vv.vcode) = v_vcode
        AND NOT (
          vv.deleted_at IS NOT NULL
          AND vv.source_vacancy_import_batch_id IS NOT NULL
        )
    ) THEN
      v_is_existing := true;
      v_errs := v_errs || '[{"field":"VCODE","msg":"VCODE already exists in OHMployee and cannot be imported (migration import is for new or previously rolled-back VCODEs only)"}]'::jsonb;
      v_exist_vcode := v_exist_vcode + 1;
    END IF;

    -- Derive Open vs Pipeline from applicant fields
    v_has_app := (v_app_last IS NOT NULL OR v_app_first IS NOT NULL);
    v_tab := CASE WHEN v_has_app THEN 'pipeline' ELSE 'open' END;

    -- ── Cross-account active applicant duplicate precheck (OHM2026_1150) ──
    IF v_has_app
       AND v_app_last  IS NOT NULL
       AND v_app_first IS NOT NULL
       AND v_contact   IS NOT NULL THEN

      SELECT v2.account,
             COALESCE(g2.group_name, 'Unknown Group'),
             a2.status
        INTO v_conflict_acct, v_conflict_grp, v_conflict_status
      FROM public.applicants a2
      JOIN public.vacancies   v2    ON v2.vcode = a2.vacancy_vcode
      LEFT JOIN public.accounts acct2 ON acct2.id = v2.account_id
      LEFT JOIN public.groups   g2    ON g2.id = acct2.group_id
      WHERE v2.deleted_at              IS NULL
        AND v2.account_id              IS NOT NULL
        AND v2.account_id              IS DISTINCT FROM p_account_id
        AND COALESCE(a2.is_archived, false) = false
        AND public.fn_is_active_vacancy_applicant_status(a2.status)
        AND lower(btrim(COALESCE(a2.last_name,      ''))) = lower(btrim(v_app_last))
        AND lower(btrim(COALESCE(a2.first_name,     ''))) = lower(btrim(v_app_first))
        AND       btrim(COALESCE(a2.contact_number, '')) =       btrim(v_contact)
      ORDER BY a2.created_at
      LIMIT 1;

      IF FOUND AND v_conflict_acct IS NOT NULL THEN
        v_errs := v_errs || jsonb_build_array(jsonb_build_object(
          'field',     'APPLICANT',
          'msg',       'Applicant has an active application under ' ||
                       v_conflict_grp || ' - ' || v_conflict_acct || ' Account.' ||
                       CASE WHEN v_conflict_status IS NOT NULL
                            THEN chr(10) || 'Current Status: ' ||
                                 initcap(replace(v_conflict_status, '_', ' ')) || '.'
                            ELSE ''
                       END,
          'next_step', format(
            'Review the active application under %s - %s Account first. If the applicant will proceed under this account instead, close, reject, or complete the existing application before importing here.',
            v_conflict_grp,
            v_conflict_acct
          )
        ));
        v_cross_acct := v_cross_acct + 1;
      END IF;
    END IF;
    -- ── End cross-account precheck ────────────────────────────────────────

    -- Status determination
    IF jsonb_array_length(v_errs) > 0 THEN
      v_status := 'blocked';
    ELSIF jsonb_array_length(v_flags) > 0 THEN
      v_status := 'flagged';
    ELSE
      v_status := 'valid';
    END IF;

    INSERT INTO public.vacancy_import_rows (
      batch_id, row_number, raw_data,
      vcode, group_name, chain, account_name, store_name, position,
      hc_raw, employment_type, request_type_raw, request_type_norm,
      vacant_date_raw, province, city, target_fill_date_raw, hrco, contact_number,
      with_penalty_raw, with_penalty_norm,
      applicant_last_name, applicant_first_name, applicant_middle_name,
      applicant_status, applicant_source,
      migration_source, migration_notes,
      derived_tab, validation_status, validation_errors, validation_flags,
      is_existing_vcode
    ) VALUES (
      v_batch_id, v_idx, v_row,
      v_vcode, v_csv_group, v_chain, v_csv_acct, v_store_nm, v_position,
      v_hc_raw, v_emp_type, v_req_raw, v_req_norm,
      v_vacant_raw, v_prov, v_city, v_tfd_raw, v_hrco, v_contact,
      v_pen_raw, v_pen_norm,
      v_app_last, v_app_first, v_app_mid,
      v_app_status, v_app_source,
      v_mig_source, v_mig_notes,
      v_tab, v_status, v_errs, v_flags,
      v_is_existing
    );

    -- Counters
    CASE v_status
      WHEN 'valid'   THEN v_valid   := v_valid   + 1;
      WHEN 'flagged' THEN v_flagged := v_flagged + 1;
      WHEN 'skipped' THEN v_skipped := v_skipped + 1;
      WHEN 'blocked' THEN v_blocked := v_blocked + 1;
      ELSE NULL;
    END CASE;
    IF v_status IN ('valid','flagged') THEN
      IF v_tab = 'pipeline' THEN v_pipeline := v_pipeline + 1;
      ELSE v_open := v_open + 1;
      END IF;
    END IF;
  END LOOP;

  -- Distinct VCODEs duplicated within upload
  SELECT count(*) INTO v_dup_vcode FROM _vib_dup_vcodes;

  -- Aggregate blocking error summary
  SELECT COALESCE(jsonb_object_agg(field_name, cnt), '{}'::jsonb) INTO v_summary
    FROM (
      SELECT (e.value->>'field') AS field_name, count(*) AS cnt
        FROM public.vacancy_import_rows r
        CROSS JOIN LATERAL jsonb_array_elements(r.validation_errors) AS e(value)
       WHERE r.batch_id = v_batch_id
       GROUP BY 1
    ) s;

  -- OHM2026_1151: a batch with ANY blocked rows must never reach
  -- pending_approval — always set validation_failed so the approval
  -- path remains unavailable until the user corrects and re-uploads.
  v_final := CASE
    WHEN v_blocked > 0             THEN 'validation_failed'
    WHEN (v_valid + v_flagged) = 0 THEN 'validation_failed'
    ELSE                               'pending_approval'
  END;

  UPDATE public.vacancy_import_batches
     SET total_rows                    = v_total,
         valid_rows                    = v_valid,
         flagged_rows                  = v_flagged,
         skipped_rows                  = v_skipped,
         blocked_rows                  = v_blocked,
         open_count                    = v_open,
         pipeline_count                = v_pipeline,
         duplicate_vcode_count         = v_dup_vcode,
         existing_vcode_count          = v_exist_vcode,
         context_mismatch_count        = v_ctx_mismatch,
         cross_account_applicant_count = v_cross_acct,
         error_summary                 = v_summary,
         status                        = v_final,
         updated_at                    = now()
   WHERE id = v_batch_id;

  RETURN jsonb_build_object(
    'batch_id',                        v_batch_id,
    'status',                          v_final,
    'total_rows',                      v_total,
    'valid_rows',                      v_valid,
    'flagged_rows',                    v_flagged,
    'skipped_rows',                    v_skipped,
    'blocked_rows',                    v_blocked,
    'open_count',                      v_open,
    'pipeline_count',                  v_pipeline,
    'duplicate_vcode_count',           v_dup_vcode,
    'existing_vcode_count',            v_exist_vcode,
    'context_mismatch_count',          v_ctx_mismatch,
    'cross_account_applicant_count',   v_cross_acct,
    'error_summary',                   v_summary
  );
END$func$;

REVOKE ALL ON FUNCTION public.submit_vacancy_import(text,uuid,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_vacancy_import(text,uuid,uuid,jsonb) TO authenticated;

COMMENT ON FUNCTION public.submit_vacancy_import IS
  'OHM2026_1135 dry-run validation. '
  'OHM2026_1150: cross-account active applicant duplicate precheck for Pipeline rows. '
  'OHM2026_1151: blocked_rows > 0 forces validation_failed (never pending_approval); '
  'conflict msg enriched with group name, account name, and current applicant status. '
  'OHM2026_0065 SS1: VCODE existence check widened to block any non-restorable vacancy row '
  '(active, archived, soft-deleted non-import). Only soft-deleted import rows '
  '(deleted_at IS NOT NULL AND source_vacancy_import_batch_id IS NOT NULL) are allowed '
  'through because approve_vacancy_import restores them in place. '
  'RBAC: Encoder / Head Admin / Super Admin.';


-- ============================================================
-- §2  SS3 — Override deployment_type to Roving for multi-store
--           employees in approve_plantilla_import_batch
-- ============================================================
-- Full replacement of approve_plantilla_import_batch.
-- Only change vs 20260803000000: after the CASE block that
-- normalises v_deployment_type from the XLSX value, a new
-- four-line block overrides it to 'Roving' whenever v_store_cnt > 1.
-- All other logic (Phase A store upsert, Phase B employee upsert,
-- VCODE resolution guard, optional enrichment, MIKA source-of-truth,
-- OHM2026_1044/1144/1145) is preserved verbatim.
-- ============================================================

CREATE OR REPLACE FUNCTION public.approve_plantilla_import_batch(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid        uuid := auth.uid();
  v_actor      uuid := public.get_current_profile_id();
  v_batch      public.plantilla_import_batches%ROWTYPE;
  v_acct_name  text;

  -- Phase A locals
  v_srow               record;
  v_existing_store_id  uuid;
  v_new_store_id       uuid;
  v_old_store_snap     jsonb;
  v_pen_bool           boolean;
  v_emp_type_norm      text;
  v_stores_done        int := 0;

  -- Phase B locals
  v_emp_rec        record;
  v_store_rec      record;
  v_plantilla_id   uuid;
  v_roving_id      uuid;
  v_store_cnt      int;
  v_filled         numeric(8,4);
  v_emp_name       text;
  v_old_plant_snap jsonb;
  v_employees_done int := 0;
  v_alloc_done     int := 0;

  -- Optional enrichment parsing
  v_daily_rate_parsed  numeric;
  v_birthdate_parsed   date;
  v_deployment_type    text;
  v_area_val           text;
  v_has_penalty        boolean;

  -- Commit counts
  v_committable int;

  -- VCODE resolution guard
  v_unresolved_vcode text;

  -- Humanised error
  v_err_state text;
  v_err_msg   text;
  v_err_out   text;
BEGIN
  -- ── Auth ─────────────────────────────────────────────────────────────────
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Lock + state check ───────────────────────────────────────────────────
  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  -- ── Pre-commit guard ─────────────────────────────────────────────────────
  SELECT count(*) INTO v_committable
    FROM public.plantilla_import_rows
   WHERE batch_id = p_batch_id
     AND validation_status IN ('valid','flagged')
     AND employee_no IS NOT NULL
     AND vcode IS NOT NULL;

  IF v_committable = 0 THEN
    RAISE EXCEPTION 'COMMIT_EMPTY: no committable rows in batch (valid+flagged with employee_no and vcode)'
      USING ERRCODE = '22023';
  END IF;

  SELECT account_name INTO v_acct_name
    FROM public.accounts WHERE id = v_batch.selected_account_id;

  -- ── Temp store commit map ─────────────────────────────────────────────────
  DROP TABLE IF EXISTS _pib_store_map;
  CREATE TEMP TABLE _pib_store_map (
    vcode    text,
    store_id uuid,
    is_new   boolean
  ) ON COMMIT DROP;

  -- ── Inner exception block — all commit DML is atomic ─────────────────────
  BEGIN

    -- ── Phase A: Store upsert ───────────────────────────────────────────────
    FOR v_srow IN
      SELECT DISTINCT ON (vcode)
             vcode, store_name, area_province, area_city,
             employment_type, with_penalty_raw, row_number, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid','flagged')
         AND vcode IS NOT NULL
       ORDER BY vcode, row_number
    LOOP
      v_emp_type_norm := CASE
        WHEN lower(COALESCE(v_srow.employment_type,'')) IN ('stationary','roving')
          THEN lower(v_srow.employment_type)
        ELSE NULL
      END;

      v_pen_bool := CASE
        WHEN lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('yes','y','true','1')  THEN true
        WHEN lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('no','n','false','0') THEN false
        ELSE NULL
      END;

      SELECT to_jsonb(s.*) INTO v_old_store_snap
        FROM public.stores s
       WHERE upper(s.vcode) = upper(v_srow.vcode) AND s.status = 'active'
       ORDER BY s.created_at LIMIT 1;

      IF v_old_store_snap IS NULL THEN
        INSERT INTO public.stores (
          vcode, store_name, area_province, area_city,
          employment_type, with_penalty,
          group_id, account_id, status,
          created_by, updated_by, approved_by, approved_at, source_import_id
        ) VALUES (
          v_srow.vcode, v_srow.store_name, v_srow.area_province, v_srow.area_city,
          v_emp_type_norm, v_pen_bool,
          v_batch.selected_group_id, v_batch.selected_account_id, 'active',
          v_uid, v_uid, v_uid, now(), p_batch_id
        ) RETURNING id INTO v_new_store_id;

        INSERT INTO _pib_store_map VALUES (upper(v_srow.vcode), v_new_store_id, true);

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_new_store_id, 'insert', NULL, v_uid);

      ELSE
        v_existing_store_id := (v_old_store_snap->>'id')::uuid;

        UPDATE public.stores
           SET store_name      = v_srow.store_name,
               area_province   = v_srow.area_province,
               area_city       = v_srow.area_city,
               employment_type = COALESCE(v_emp_type_norm, employment_type),
               with_penalty    = COALESCE(v_pen_bool, with_penalty),
               updated_by      = v_uid,
               approved_by     = v_uid,
               approved_at     = now(),
               source_import_id = p_batch_id
         WHERE id = v_existing_store_id;

        INSERT INTO _pib_store_map VALUES (upper(v_srow.vcode), v_existing_store_id, false);

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_existing_store_id, 'update', v_old_store_snap, v_uid);
      END IF;

      UPDATE public.plantilla_import_rows
         SET previous_store_snapshot = v_old_store_snap
       WHERE batch_id = p_batch_id
         AND upper(vcode) = upper(v_srow.vcode)
         AND validation_status IN ('valid','flagged');

      v_stores_done := v_stores_done + 1;
    END LOOP;

    -- ── Post-Phase-A: VCODE resolution guard (OHM2026_1144) ──────────────────
    SELECT r.vcode INTO v_unresolved_vcode
      FROM public.plantilla_import_rows r
     WHERE r.batch_id = p_batch_id
       AND r.validation_status IN ('valid','flagged')
       AND r.vcode IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM _pib_store_map sm WHERE sm.vcode = upper(r.vcode)
       )
     LIMIT 1;

    IF v_unresolved_vcode IS NOT NULL THEN
      RAISE EXCEPTION 'STORE_RESOLUTION_FAILED: VCODE % not resolved after store upsert — cannot commit plantilla rows',
        v_unresolved_vcode
        USING ERRCODE = '23503';
    END IF;

    -- ── Phase B: Employee / plantilla upsert ────────────────────────────────
    -- Aggregate per-employee: identity + position/area fields + optional enrichment.
    -- All fields use first-non-null per employee (ORDER BY row_number).
    FOR v_emp_rec IN
      SELECT
        employee_no,
        count(DISTINCT vcode)                                                       AS store_count,
        -- Identity
        (array_agg(last_name   ORDER BY row_number))[1]                            AS last_name,
        (array_agg(first_name  ORDER BY row_number))[1]                            AS first_name,
        (array_agg(middle_name ORDER BY row_number))[1]                            AS middle_name,
        -- Position / deployment
        (array_agg(position          ORDER BY row_number)
           FILTER (WHERE position IS NOT NULL))[1]                                 AS position,
        (array_agg(employment_type   ORDER BY row_number)
           FILTER (WHERE employment_type IS NOT NULL))[1]                          AS employment_type_raw,
        (array_agg(with_penalty_raw  ORDER BY row_number)
           FILTER (WHERE with_penalty_raw IS NOT NULL))[1]                         AS with_penalty_raw_agg,
        (array_agg(area_province     ORDER BY row_number)
           FILTER (WHERE area_province IS NOT NULL))[1]                            AS area_province,
        (array_agg(area_city         ORDER BY row_number)
           FILTER (WHERE area_city IS NOT NULL))[1]                                AS area_city,
        -- Optional enrichment fields (OHM2026_0080)
        (array_agg(civil_status      ORDER BY row_number)
           FILTER (WHERE civil_status    IS NOT NULL))[1]                          AS civil_status,
        (array_agg(rate_raw          ORDER BY row_number)
           FILTER (WHERE rate_raw        IS NOT NULL))[1]                          AS rate_raw,
        (array_agg(birthdate_raw     ORDER BY row_number)
           FILTER (WHERE birthdate_raw   IS NOT NULL))[1]                          AS birthdate_raw,
        (array_agg(contact_raw       ORDER BY row_number)
           FILTER (WHERE contact_raw     IS NOT NULL))[1]                          AS contact_raw,
        (array_agg(address_raw       ORDER BY row_number)
           FILTER (WHERE address_raw     IS NOT NULL))[1]                          AS address_raw,
        (array_agg(schedule_raw      ORDER BY row_number)
           FILTER (WHERE schedule_raw    IS NOT NULL))[1]                          AS schedule_raw,
        (array_agg(dayoff_raw        ORDER BY row_number)
           FILTER (WHERE dayoff_raw      IS NOT NULL))[1]                          AS dayoff_raw,
        (array_agg(coordinator_raw   ORDER BY row_number)
           FILTER (WHERE coordinator_raw IS NOT NULL))[1]                          AS coordinator_raw
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid','flagged')
         AND employee_no IS NOT NULL
       GROUP BY employee_no
    LOOP
      v_employees_done := v_employees_done + 1;
      v_store_cnt := v_emp_rec.store_count;
      v_filled    := round(1.0 / GREATEST(v_store_cnt, 1), 4);
      v_emp_name  := v_emp_rec.last_name || ', ' || v_emp_rec.first_name
                     || COALESCE(' ' || v_emp_rec.middle_name, '');

      -- Normalise deployment_type from XLSX (Stationary/Roving for display consistency)
      v_deployment_type := CASE
        WHEN lower(COALESCE(v_emp_rec.employment_type_raw,'')) = 'stationary' THEN 'Stationary'
        WHEN lower(COALESCE(v_emp_rec.employment_type_raw,'')) = 'roving'     THEN 'Roving'
        ELSE NULLIF(trim(COALESCE(v_emp_rec.employment_type_raw,'')), '')
      END;

      -- ── OHM2026_0065 SS3: Backend roving override ────────────────────────
      -- An employee with rows in multiple VCODEs is structurally Roving
      -- regardless of what the XLSX EMPLOYMENT_TYPE column says.
      -- The XLSX column is not trusted for roving detection; the multi-store
      -- count is authoritative.  UI displays the backend-computed value only.
      IF v_store_cnt > 1 THEN
        v_deployment_type := 'Roving';
      END IF;
      -- ─────────────────────────────────────────────────────────────────────

      -- area: prefer city over province for specificity
      v_area_val := NULLIF(trim(COALESCE(
        v_emp_rec.area_city,
        v_emp_rec.area_province,
        ''
      )), '');

      -- has_penalty
      v_has_penalty := CASE
        WHEN lower(COALESCE(v_emp_rec.with_penalty_raw_agg,'')) IN ('yes','y','true','1')  THEN true
        WHEN lower(COALESCE(v_emp_rec.with_penalty_raw_agg,'')) IN ('no','n','false','0') THEN false
        ELSE NULL
      END;

      -- Parse optional numeric/date fields (silent failure → null, never blocks)
      v_daily_rate_parsed := NULL;
      BEGIN
        v_daily_rate_parsed := nullif(trim(coalesce(v_emp_rec.rate_raw, '')), '')::numeric;
      EXCEPTION WHEN OTHERS THEN
        v_daily_rate_parsed := NULL;
      END;

      v_birthdate_parsed := NULL;
      BEGIN
        v_birthdate_parsed := nullif(trim(coalesce(v_emp_rec.birthdate_raw, '')), '')::date;
      EXCEPTION WHEN OTHERS THEN
        v_birthdate_parsed := NULL;
      END;

      -- Roving group for multi-store employees
      v_roving_id := NULL;
      IF v_store_cnt > 1 THEN
        INSERT INTO public.import_roving_groups (
          employee_no, account_id, group_id, account_name, label,
          active_store_count, filled_hc_per_store, source_import_batch_id, created_by
        ) VALUES (
          v_emp_rec.employee_no,
          v_batch.selected_account_id, v_batch.selected_group_id,
          v_acct_name, v_emp_name || ' — Roving',
          v_store_cnt, v_filled, p_batch_id, v_actor
        ) RETURNING id INTO v_roving_id;
      END IF;

      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no
         AND is_deleted = false
         AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
       LIMIT 1;

      SELECT to_jsonb(p.*) INTO v_old_plant_snap
        FROM public.plantilla p WHERE id = v_plantilla_id;

      IF v_plantilla_id IS NULL THEN
        -- New employee: insert plantilla master with all profile fields.
        -- OHM2026_1144: plantilla.vcode persisted for single-store rows.
        INSERT INTO public.plantilla (
          employee_name, employee_no, emploc_no, account, status,
          account_id, last_name, first_name, middle_name,
          roving_assignment_id, is_pool_employee,
          -- position / deployment
          position, deployment_type, has_penalty, area, area_name_snapshot,
          -- store lineage
          vcode, store_id, store_name,
          -- optional enrichment fields (OHM2026_0080)
          civil_status, daily_rate, birthdate,
          contact_no, address, schedule, dayoff, coordinator,
          source_baseline_import_batch_id, created_by, moved_by_user_id
        )
        SELECT
          v_emp_name, v_emp_rec.employee_no, v_emp_rec.employee_no,
          v_acct_name, 'Active',
          v_batch.selected_account_id,
          v_emp_rec.last_name, v_emp_rec.first_name, v_emp_rec.middle_name,
          NULL, false,
          -- position / deployment
          nullif(trim(coalesce(v_emp_rec.position, '')), ''),
          v_deployment_type,
          v_has_penalty,
          v_area_val,
          v_area_val,   -- area_name_snapshot mirrors area
          -- store: single-store pins VCODE/store; roving leaves null
          CASE WHEN v_store_cnt = 1 THEN r.vcode     ELSE NULL END,
          CASE WHEN v_store_cnt = 1 THEN sm.store_id ELSE NULL END,
          CASE WHEN v_store_cnt = 1 THEN r.store_name ELSE NULL END,
          -- optional enrichment
          nullif(trim(coalesce(v_emp_rec.civil_status, '')),    ''),
          v_daily_rate_parsed,
          v_birthdate_parsed,
          nullif(trim(coalesce(v_emp_rec.contact_raw, '')),     ''),
          nullif(trim(coalesce(v_emp_rec.address_raw, '')),     ''),
          nullif(trim(coalesce(v_emp_rec.schedule_raw, '')),    ''),
          nullif(trim(coalesce(v_emp_rec.dayoff_raw, '')),      ''),
          nullif(trim(coalesce(v_emp_rec.coordinator_raw, '')), ''),
          p_batch_id, v_actor, v_actor
        FROM (
          SELECT vcode, store_name
            FROM public.plantilla_import_rows
           WHERE batch_id = p_batch_id AND employee_no = v_emp_rec.employee_no
             AND validation_status IN ('valid','flagged')
           ORDER BY row_number LIMIT 1
        ) r
        LEFT JOIN _pib_store_map sm ON sm.vcode = upper(r.vcode)
        RETURNING id INTO v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'insert', NULL, v_uid);

      ELSE
        -- Existing employee: refresh name + import linkage + fill blank profile fields.
        -- MIKA source-of-truth: contact_no and address are only filled when currently blank.
        -- position/area/deployment_type: COALESCE fill (import wins when currently blank).
        -- Optional enrichment: COALESCE fill (import wins when currently blank).
        UPDATE public.plantilla
           SET employee_name    = v_emp_name,
               last_name        = v_emp_rec.last_name,
               first_name       = v_emp_rec.first_name,
               middle_name      = v_emp_rec.middle_name,
               -- position / deployment: fill if currently blank
               position         = COALESCE(
                                    NULLIF(trim(COALESCE(position, '')), ''),
                                    nullif(trim(coalesce(v_emp_rec.position, '')), '')
                                  ),
               deployment_type  = COALESCE(
                                    NULLIF(trim(COALESCE(deployment_type, '')), ''),
                                    v_deployment_type
                                  ),
               has_penalty      = COALESCE(has_penalty, v_has_penalty),
               area             = COALESCE(
                                    NULLIF(trim(COALESCE(area, '')), ''),
                                    v_area_val
                                  ),
               area_name_snapshot = COALESCE(
                                      NULLIF(trim(COALESCE(area_name_snapshot, '')), ''),
                                      v_area_val
                                    ),
               -- optional enrichment: fill if currently blank
               civil_status     = COALESCE(
                                    NULLIF(trim(COALESCE(civil_status, '')), ''),
                                    nullif(trim(coalesce(v_emp_rec.civil_status, '')), '')
                                  ),
               daily_rate       = COALESCE(daily_rate, v_daily_rate_parsed),
               birthdate        = COALESCE(birthdate,  v_birthdate_parsed),
               -- MIKA source-of-truth: contact_no / address preserved if non-blank
               contact_no       = CASE
                                    WHEN NULLIF(trim(COALESCE(contact_no, '')), '') IS NOT NULL
                                    THEN contact_no
                                    ELSE nullif(trim(coalesce(v_emp_rec.contact_raw, '')), '')
                                  END,
               address          = CASE
                                    WHEN NULLIF(trim(COALESCE(address, '')), '') IS NOT NULL
                                    THEN address
                                    ELSE nullif(trim(coalesce(v_emp_rec.address_raw, '')), '')
                                  END,
               schedule         = COALESCE(
                                    NULLIF(trim(COALESCE(schedule, '')), ''),
                                    nullif(trim(coalesce(v_emp_rec.schedule_raw, '')), '')
                                  ),
               dayoff           = COALESCE(
                                    NULLIF(trim(COALESCE(dayoff, '')), ''),
                                    nullif(trim(coalesce(v_emp_rec.dayoff_raw, '')), '')
                                  ),
               coordinator      = COALESCE(
                                    NULLIF(trim(COALESCE(coordinator, '')), ''),
                                    nullif(trim(coalesce(v_emp_rec.coordinator_raw, '')), '')
                                  ),
               updated_at       = now(),
               source_baseline_import_batch_id = p_batch_id
         WHERE id = v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'update', v_old_plant_snap, v_uid);
      END IF;

      IF v_roving_id IS NOT NULL THEN
        UPDATE public.import_roving_groups SET plantilla_id = v_plantilla_id
         WHERE id = v_roving_id;
      END IF;

      UPDATE public.plantilla_import_rows
         SET previous_plantilla_snapshot = v_old_plant_snap
       WHERE batch_id = p_batch_id
         AND employee_no = v_emp_rec.employee_no
         AND validation_status IN ('valid','flagged');

      INSERT INTO public.plantilla_import_commit_snapshots
        (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
      SELECT
        p_batch_id, 'allocation', a.id, 'update', to_jsonb(a.*), v_uid
        FROM public.employee_store_allocations a
       WHERE a.employee_no = v_emp_rec.employee_no
         AND a.is_active
         AND a.account_id = v_batch.selected_account_id;

      UPDATE public.employee_store_allocations
         SET is_active = false, effective_end = CURRENT_DATE
       WHERE employee_no = v_emp_rec.employee_no
         AND is_active
         AND account_id = v_batch.selected_account_id;

      FOR v_store_rec IN
        SELECT DISTINCT ON (pir.vcode)
               pir.vcode, sm.store_id,
               pir.store_name, pir.resolved_account_id, pir.resolved_group_id
          FROM public.plantilla_import_rows pir
          LEFT JOIN _pib_store_map sm ON sm.vcode = upper(pir.vcode)
         WHERE pir.batch_id = p_batch_id
           AND pir.employee_no = v_emp_rec.employee_no
           AND pir.validation_status IN ('valid','flagged')
         ORDER BY pir.vcode, pir.row_number
      LOOP
        INSERT INTO public.employee_store_allocations (
          plantilla_id, employee_no, roving_group_id,
          store_id, vcode, store_name,
          account_id, group_id,
          filled_hc, active_store_count,
          effective_start, is_active,
          source_import_batch_id, created_by
        ) VALUES (
          v_plantilla_id, v_emp_rec.employee_no, v_roving_id,
          v_store_rec.store_id, v_store_rec.vcode, v_store_rec.store_name,
          COALESCE(v_store_rec.resolved_account_id, v_batch.selected_account_id),
          COALESCE(v_store_rec.resolved_group_id,   v_batch.selected_group_id),
          v_filled, v_store_cnt,
          CURRENT_DATE, true,
          p_batch_id, v_actor
        );
        v_alloc_done := v_alloc_done + 1;
      END LOOP;

      INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
      VALUES (v_uid, 'plantilla_import', 'APPROVAL', v_plantilla_id,
        jsonb_build_object(
          'employee_no',         v_emp_rec.employee_no,
          'store_count',         v_store_cnt,
          'filled_hc_per_store', v_filled,
          'roving',              (v_roving_id IS NOT NULL),
          'batch_id',            p_batch_id
        ));
    END LOOP;

    UPDATE public.plantilla_import_batches
       SET status             = 'approved',
           approved_by        = v_uid,
           approved_at        = now(),
           committed_stores   = v_stores_done,
           committed_employees= v_employees_done,
           rollback_ready     = true,
           updated_at         = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
    VALUES (v_uid, 'plantilla_import_batches', 'APPROVAL', p_batch_id,
      jsonb_build_object(
        'stores',      v_stores_done,
        'employees',   v_employees_done,
        'allocations', v_alloc_done
      ));

    RETURN jsonb_build_object(
      'batch_id',            p_batch_id,
      'status',              'approved',
      'stores_committed',    v_stores_done,
      'employees_committed', v_employees_done,
      'allocations_created', v_alloc_done
    );

  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_err_state = RETURNED_SQLSTATE,
      v_err_msg   = MESSAGE_TEXT;

    IF v_err_state = '23505'
       AND position('uq_plantilla_vcode_active_occupied' IN COALESCE(v_err_msg,'')) > 0
    THEN
      v_err_out := 'VCODE_ALREADY_OCCUPIED: a VCODE in this batch is already held '
                || 'by another active employee in plantilla — only one active '
                || 'occupancy per VCODE is allowed';
    ELSE
      v_err_out := format('[%s] %s', v_err_state, v_err_msg);
    END IF;

    UPDATE public.plantilla_import_batches
       SET status              = 'commit_failed',
           commit_error_detail = v_err_out,
           updated_at          = now()
     WHERE id = p_batch_id;

    RETURN jsonb_build_object(
      'batch_id', p_batch_id,
      'status',   'commit_failed',
      'error',    v_err_out
    );
  END;

END$func$;

REVOKE ALL ON FUNCTION public.approve_plantilla_import_batch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_batch(uuid) TO authenticated;

COMMENT ON FUNCTION public.approve_plantilla_import_batch IS
  'OHM2026_1044: Canonical merge of all approve_plantilla_import_batch layers. '
  'Restores position/deployment_type/area/has_penalty hydration (lost from OHM2026_0062) '
  'and optional enrichment field commit: civil_status, daily_rate, birthdate, contact_no, '
  'address, schedule, dayoff, coordinator (lost from OHM2026_0080). '
  'Preserves OHM2026_1144/1145: VCODE resolution guard, vcode persisted for single-store '
  'rows, humanised VCODE_ALREADY_OCCUPIED error, audit enum APPROVAL. '
  'MIKA source-of-truth: contact_no/address preserved if non-blank on existing employees. '
  'All other fields: COALESCE-fill (import value wins when currently blank). '
  'OHM2026_0065 SS3: v_store_cnt > 1 overrides deployment_type to ''Roving'' regardless '
  'of the XLSX EMPLOYMENT_TYPE value. The XLSX column is not trusted for roving detection; '
  'the multi-store count is authoritative. '
  'RBAC: Head Admin / Super Admin only.';


-- ============================================================
-- Validation queries (run manually after applying)
--
--   SS1 — VCODE blocked before approval:
--   V1  Attempt submit_vacancy_import with a VCODE that has an
--       active vacancy → row must be blocked, batch must be
--       validation_failed.
--   V2  Attempt submit_vacancy_import with a VCODE that has a
--       soft-deleted NON-import vacancy
--       (deleted_at IS NOT NULL, source_vacancy_import_batch_id IS NULL)
--       → row must be blocked (is_existing_vcode=true), batch must
--       be validation_failed. Previously this reached pending_approval
--       and exploded with duplicate key at commit time.
--   V3  Attempt submit_vacancy_import with a VCODE that has a
--       soft-deleted IMPORT vacancy
--       (deleted_at IS NOT NULL, source_vacancy_import_batch_id IS NOT NULL)
--       → row must be valid (restorable), batch may reach pending_approval,
--       approve must restore the row in place.
--
--   SS3 — Roving type override:
--   V4  Import a batch where one employee appears in 2+ VCODEs with
--       EMPLOYMENT_TYPE = 'Stationary' in the CSV.
--       After approve, SELECT deployment_type FROM plantilla
--         WHERE source_baseline_import_batch_id = '<batch_id>'
--         AND employee_no = '<multi_store_employee_no>';
--       Expected: 'Roving' (not 'Stationary').
--   V5  Import a batch where one employee appears in 1 VCODE with
--       EMPLOYMENT_TYPE = 'Stationary'.
--       After approve, deployment_type should remain 'Stationary'.
--   V6  Import a batch where one employee appears in 2+ VCODEs with
--       EMPLOYMENT_TYPE = 'Roving'. deployment_type should remain 'Roving'.
-- ============================================================
