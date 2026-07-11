-- ============================================================
-- OHM2026_0071 — Enforce global archived VCODE conflict blocking
-- Migration:  20261006000000_enforce_archived_vcode_conflict_blocking.sql
-- Depends on: 20260603000002_fix_vcode_import_duplicate_check_and_roving_type.sql
--             20260909000000_import_rollback_governance_72_business_hours.sql
-- ============================================================
-- Purpose
--   When an imported/uploaded VCODE already exists in OHMployee and the
--   matched existing record is archived, rolled-back, or soft-deleted
--   (previously used), the row must be BLOCKED with a distinct conflict
--   type so the UI can surface the correct badge and message instead of
--   defaulting to the generic "already exists" copy.
--
-- Changes
--   §1  Add archived_vcode_count column to vacancy_import_batches.
--   §2  Rewrite submit_vacancy_import — split VCODE existence check into:
--         (a) archived / previously-used → conflict_type = 'archived_vcode'
--         (b) active non-restorable     → conflict_type = 'active_vcode'
--       Both are still blocked. The difference is the conflict_type key
--       included in validation_errors and the human-readable message.
--   §3  Refresh get_vacancy_import_batches to expose archived_vcode_count.
--
-- Replay safety
--   §1  ADD COLUMN IF NOT EXISTS — idempotent DDL.
--   §2  CREATE OR REPLACE — idempotent function rewrite.
--   §3  DROP + CREATE OR REPLACE — idempotent.
-- ============================================================


-- ============================================================
-- §1  archived_vcode_count column on vacancy_import_batches
-- ============================================================

ALTER TABLE public.vacancy_import_batches
  ADD COLUMN IF NOT EXISTS archived_vcode_count integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.vacancy_import_batches.archived_vcode_count IS
  'Count of rows blocked because the VCODE already exists as archived or '
  'previously-used (is_archived=true, status=Archived, or soft-deleted non-import). '
  'Subset of existing_vcode_count. Added by OHM2026_0071.';


-- ============================================================
-- §2  submit_vacancy_import — split VCODE existence check
-- ============================================================
-- Full replacement. Only change vs 20260603000002:
--   • Added v_existing_is_archived boolean and v_archived_vcode int to DECLARE.
--   • Replaced single VCODE existence check with a two-step SELECT that:
--       1. Queries the first non-restorable matching row.
--       2. Classifies it as archived/previously-used vs active.
--       3. Includes conflict_type key in the validation_errors JSON object.
--       4. Increments v_archived_vcode when archived.
--   • UPDATE and RETURN now include archived_vcode_count.
-- All other logic (auth, scope, cross-account precheck, OHM2026_1150/1151)
-- is preserved verbatim from 20260603000002.
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

  -- OHM2026_0071: archived VCODE detection
  v_existing_is_archived boolean;

  -- Cross-account applicant precheck (OHM2026_1150 + OHM2026_1151)
  v_conflict_acct    text;
  v_conflict_grp     text;
  v_conflict_status  text;

  -- Batch counters
  v_total          int := 0;
  v_valid          int := 0;
  v_flagged        int := 0;
  v_skipped        int := 0;
  v_blocked        int := 0;
  v_open           int := 0;
  v_pipeline       int := 0;
  v_dup_vcode      int := 0;
  v_exist_vcode    int := 0;
  v_archived_vcode int := 0;   -- OHM2026_0071: subset of v_exist_vcode
  v_ctx_mismatch   int := 0;
  v_cross_acct     int := 0;

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

    -- ── OHM2026_0071: Archived/previously-used VCODE conflict blocking ────────
    -- Split the existence check into two categories:
    --   (a) archived / previously-used (is_archived=true, status=Archived, or
    --       soft-deleted non-import row) → conflict_type 'archived_vcode'
    --       Message: "VCODE already exists ... as archived/previously used"
    --   (b) active non-restorable → conflict_type 'active_vcode'
    --       Message: "VCODE already exists ... and cannot be imported"
    -- Both remain BLOCKED. "Restorable" rows (soft-deleted import rows with
    -- source_vacancy_import_batch_id IS NOT NULL) are still allowed through —
    -- approve_vacancy_import restores them in place (OHM2026_0065 SS1).
    -- ─────────────────────────────────────────────────────────────────────────
    IF v_vcode IS NOT NULL THEN
      SELECT
        COALESCE(vv.is_archived, false)
        OR vv.status = ANY(ARRAY['Archived'])
        OR (vv.deleted_at IS NOT NULL AND vv.source_vacancy_import_batch_id IS NULL)
      INTO v_existing_is_archived
      FROM public.vacancies vv
      WHERE upper(vv.vcode) = v_vcode
        AND NOT (
          vv.deleted_at IS NOT NULL
          AND vv.source_vacancy_import_batch_id IS NOT NULL
        )
      LIMIT 1;

      IF FOUND THEN
        v_is_existing := true;
        v_exist_vcode := v_exist_vcode + 1;
        IF v_existing_is_archived THEN
          v_archived_vcode := v_archived_vcode + 1;
          v_errs := v_errs || jsonb_build_array(jsonb_build_object(
            'field',         'VCODE',
            'conflict_type', 'archived_vcode',
            'msg',           'VCODE already exists in OHMployee as archived/previously used and cannot be reused.'
          ));
        ELSE
          v_errs := v_errs || jsonb_build_array(jsonb_build_object(
            'field',         'VCODE',
            'conflict_type', 'active_vcode',
            'msg',           'VCODE already exists in OHMployee and cannot be imported (migration import is for new VCODEs only).'
          ));
        END IF;
      END IF;
    END IF;
    -- ── End OHM2026_0071 VCODE conflict blocking ─────────────────────────────

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
         archived_vcode_count          = v_archived_vcode,
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
    'archived_vcode_count',            v_archived_vcode,
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
  'OHM2026_1151: blocked_rows > 0 forces validation_failed (never pending_approval). '
  'OHM2026_0065 SS1: VCODE existence check covers active, archived, and soft-deleted non-import rows. '
  'OHM2026_0071: VCODE check split — archived/previously-used rows use conflict_type=archived_vcode; '
  'active rows use conflict_type=active_vcode. archived_vcode_count tracks archived conflicts. '
  'RBAC: Encoder / Head Admin / Super Admin.';


-- ============================================================
-- §3  Refresh get_vacancy_import_batches — add archived_vcode_count
-- ============================================================
-- Full replacement of the latest version (20260909000000).
-- Only change: archived_vcode_count integer added to RETURNS TABLE
-- and b.archived_vcode_count added to SELECT.
-- All other columns, JOINs, filters, and computed fields (rollback
-- window, rollback_ui_state, can_emergency_rollback) preserved verbatim.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_vacancy_import_batches(text);

CREATE OR REPLACE FUNCTION public.get_vacancy_import_batches(
  p_status text DEFAULT NULL
)
RETURNS TABLE (
  id                            uuid,
  file_name                     text,
  status                        text,
  selected_group_id             uuid,
  selected_account_id           uuid,
  group_name                    text,
  account_name                  text,
  uploaded_by                   uuid,
  uploaded_role                 text,
  uploaded_at                   timestamptz,
  approved_by                   uuid,
  approved_by_name              text,
  approved_at                   timestamptz,
  rejected_by                   uuid,
  rejected_by_name              text,
  rejected_at                   timestamptz,
  rejection_reason              text,
  rejection_reason_code         text,
  rejection_reason_note         text,
  commit_error_detail           text,
  total_rows                    integer,
  valid_rows                    integer,
  flagged_rows                  integer,
  skipped_rows                  integer,
  blocked_rows                  integer,
  open_count                    integer,
  pipeline_count                integer,
  duplicate_vcode_count         integer,
  existing_vcode_count          integer,
  archived_vcode_count          integer,
  context_mismatch_count        integer,
  cross_account_applicant_count integer,
  committed_vacancies           integer,
  committed_applicants          integer,
  error_summary                 jsonb,
  approval_due_at               timestamptz,
  approval_escalated_at         timestamptz,
  approval_notified_at          timestamptz,
  rollback_status               text,
  rollback_reason               text,
  rollback_reason_code          text,
  rollback_reason_note          text,
  rollback_requested_by         uuid,
  rollback_requested_by_name    text,
  rollback_requested_at         timestamptz,
  rollback_approved_by          uuid,
  rollback_approved_by_name     text,
  rollback_approved_at          timestamptz,
  rollback_completed_at         timestamptz,
  rollback_error_detail         text,
  rollback_vacancies_count      integer,
  rollback_applicants_count     integer,
  rollback_window_started_at    timestamptz,
  rollback_expires_at           timestamptz,
  rollback_remaining_seconds    integer,
  rollback_allowed              boolean,
  rollback_ui_state             text,
  rollback_block_reason         text,
  can_emergency_rollback        boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
BEGIN
  PERFORM public.finalize_expired_import_rollback_windows();

  RETURN QUERY
  SELECT
    b.id, b.file_name, b.status,
    b.selected_group_id, b.selected_account_id,
    g.group_name, a.account_name,
    b.uploaded_by, b.uploaded_role, b.created_at AS uploaded_at,
    b.approved_by,
    COALESCE(ap.full_name, ap.email, b.approved_by::text),
    b.approved_at,
    b.rejected_by,
    COALESCE(rp.full_name, rp.email, b.rejected_by::text),
    b.rejected_at,
    b.rejection_reason, b.rejection_reason_code, b.rejection_reason_note,
    b.commit_error_detail,
    b.total_rows, b.valid_rows, b.flagged_rows, b.skipped_rows, b.blocked_rows,
    b.open_count, b.pipeline_count, b.duplicate_vcode_count,
    b.existing_vcode_count,
    b.archived_vcode_count,
    b.context_mismatch_count,
    b.cross_account_applicant_count,
    b.committed_vacancies, b.committed_applicants, b.error_summary,
    b.approval_due_at, b.approval_escalated_at, b.approval_notified_at,
    b.rollback_status, b.rollback_reason,
    b.rollback_reason_code, b.rollback_reason_note,
    b.rollback_requested_by,
    COALESCE(rrp.full_name, rrp.email, b.rollback_requested_by::text),
    b.rollback_requested_at,
    b.rollback_approved_by,
    COALESCE(rap.full_name, rap.email, b.rollback_approved_by::text),
    b.rollback_approved_at,
    b.rollback_completed_at,
    b.rollback_error_detail,
    b.rollback_vacancies_count,
    b.rollback_applicants_count,
    b.rollback_window_started_at,
    b.rollback_expires_at,
    GREATEST(0, EXTRACT(EPOCH FROM (b.rollback_expires_at - now()))::int),
    b.status = 'approved'
      AND b.rollback_status IS NULL
      AND b.rollback_expires_at >= now()
      AND NOT public._import_records_modified_after_approval('vacancy', b.id, b.approved_at),
    public._import_rollback_ui_state(
      b.status,
      b.rollback_status,
      CASE
        WHEN public._import_records_modified_after_approval('vacancy', b.id, b.approved_at)
          THEN 'Records modified after import approval.'
        ELSE b.rollback_block_reason
      END,
      b.rollback_expires_at
    ),
    CASE
      WHEN public._import_records_modified_after_approval('vacancy', b.id, b.approved_at)
        THEN 'Records modified after import approval.'
      ELSE b.rollback_block_reason
    END,
    public.is_super_admin() AND b.status = 'finalized'
  FROM public.vacancy_import_batches b
  LEFT JOIN public.groups        g   ON g.id  = b.selected_group_id
  LEFT JOIN public.accounts      a   ON a.id  = b.selected_account_id
  LEFT JOIN public.users_profile ap  ON ap.auth_user_id  = b.approved_by
  LEFT JOIN public.users_profile rp  ON rp.auth_user_id  = b.rejected_by
  LEFT JOIN public.users_profile rrp ON rrp.auth_user_id = b.rollback_requested_by
  LEFT JOIN public.users_profile rap ON rap.auth_user_id = b.rollback_approved_by
  WHERE (public.i_have_full_access() OR b.uploaded_by = auth.uid())
    AND (p_status IS NULL OR b.status = p_status)
  ORDER BY b.created_at DESC;
END;
$func$;

REVOKE ALL ON FUNCTION public.get_vacancy_import_batches(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_vacancy_import_batches(text) TO authenticated;

COMMENT ON FUNCTION public.get_vacancy_import_batches(text) IS
  'Import Vacancy batches listing. '
  'OHM2026_0071: added archived_vcode_count to distinguish archived/previously-used '
  'VCODE conflicts from active VCODE conflicts.';
