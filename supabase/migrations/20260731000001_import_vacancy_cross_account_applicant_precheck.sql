-- ============================================================
-- OHMployee - Import Vacancy Cross-Account Applicant Precheck
-- Prompt ID : OHM2026_1150 + OHM2026_1151
-- Date      : 2026-05-29
-- Scope     : Import Vacancy dry-run validation ONLY
-- ============================================================
-- Problem (OHM2026_1150):
--   The DB trigger trg_assert_applicant_no_cross_account_active
--   (OHM2026_1149) correctly blocks cross-account active applicant
--   duplicates at commit time, but submit_vacancy_import (dry-run)
--   did not check for this condition — the user only discovered the
--   conflict during approval, causing a bad UX.
--
-- Fix (OHM2026_1150):
--   Add a cross-account applicant duplicate precheck inside
--   submit_vacancy_import for every Pipeline row (rows that carry
--   applicant fields). Uses the same identity predicate as the
--   existing DB trigger:
--     APPLICANT_LAST_NAME + APPLICANT_FIRST_NAME + CONTACT_NUMBER
--   and the same active-status delegate:
--     fn_is_active_vacancy_applicant_status(status).
--
-- Refinement (OHM2026_1151):
--   1. Approval gating: a batch with blocked_rows > 0 must NEVER
--      reach pending_approval. v_final is now set to
--      'validation_failed' whenever v_blocked > 0 (regardless of
--      whether valid/flagged rows also exist).
--   2. Enriched conflict message: the precheck now resolves the
--      conflicting row's group name (via accounts → groups JOIN)
--      and applicant status, surfacing them as:
--        msg:       "Applicant has an active application under
--                    Group X - ACCOUNT_NAME Account.
--                    Current Status: <status>."
--        next_step: "Review the active application under Group X -
--                    ACCOUNT_NAME Account first. If the applicant
--                    will proceed under this account instead, close,
--                    reject, or complete the existing application
--                    before importing here."
--   Not changed by OHM2026_1151:
--   * duplicate detection logic, active-status logic
--   * trigger behaviour (trg_assert_applicant_no_cross_account_active)
--   * approve_vacancy_import, rollback RPCs, notification logic
--   * Vacancy lifecycle / VCODE rules / HR Emploc / Plantilla flows
--
-- Preserved unchanged:
--   * DB trigger trg_assert_applicant_no_cross_account_active —
--     it remains the final safety net at commit time. NOT removed.
--   * approve_vacancy_import, reject_vacancy_import, all rollback
--     RPCs, and all notification logic — NOT touched.
--   * Vacancy lifecycle / Open+Pipeline classification / VCODE rules
--     / HR Emploc / Plantilla flows — NOT touched.
--
-- Allowed (NOT blocked at precheck):
--   * Same identity in the SAME account (different VCODEs) — allowed.
--   * Same identity in a different account but with a terminal /
--     archived / non-active record — allowed.
--   * Open rows (no applicant fields) — skipped entirely.
--   * Pipeline rows where APPLICANT_LAST_NAME, APPLICANT_FIRST_NAME,
--     or CONTACT_NUMBER is blank — incomplete identity, guard skipped
--     (matches trigger behaviour).
--
-- Blocked:
--   * Same identity active under a DIFFERENT account.
--   * Row validation_status = 'blocked'.
--   * Error msg: "Applicant has an active application under
--     Group X - ACCOUNT_NAME Account. Current Status: <status>."
--   * next_step guidance included in the validation_errors entry,
--     naming the conflicting group and account.
--
-- New summary counter:
--   vacancy_import_batches.cross_account_applicant_count (additive).
--   submit_vacancy_import return shape gains this key.
--   get_vacancy_import_batches gains this column in RETURNS TABLE.
--
-- Sections:
--   §1  Add cross_account_applicant_count to vacancy_import_batches
--   §2  Replace submit_vacancy_import with precheck logic
--   §3  Replace get_vacancy_import_batches to surface new column
-- ============================================================


-- ============================================================
-- §1  New counter column on vacancy_import_batches
-- ============================================================

ALTER TABLE public.vacancy_import_batches
  ADD COLUMN IF NOT EXISTS cross_account_applicant_count integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.vacancy_import_batches.cross_account_applicant_count IS
  'OHM2026_1150 — rows blocked because the applicant already holds an active '
  'application under a different account (same last+first+contact identity). '
  'Set by submit_vacancy_import dry-run; DB trigger is the final safety net.';


-- ============================================================
-- §2  Replace submit_vacancy_import (add cross-account precheck)
-- ============================================================
-- Full replacement. Only additions vs the previous version:
--   DECLARE  v_conflict_acct text; v_cross_acct int := 0;
--   ROW LOOP — new block after v_has_app determination
--   UPDATE   — cross_account_applicant_count = v_cross_acct
--   RETURN   — 'cross_account_applicant_count', v_cross_acct

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
  v_conflict_grp     text;   -- OHM2026_1151: group name of conflicting account
  v_conflict_status  text;   -- OHM2026_1151: current status of conflicting applicant

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
  v_cross_acct  int := 0;  -- OHM2026_1150

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

    -- VCODE already present in vacancies (active) → block (preserve integrity)
    IF v_vcode IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.vacancies vv
      WHERE upper(vv.vcode) = v_vcode
        AND COALESCE(vv.is_archived, false) = false
        AND vv.deleted_at IS NULL
    ) THEN
      v_is_existing := true;
      v_errs := v_errs || '[{"field":"VCODE","msg":"VCODE already exists in OHMployee — migration import is for new VCODEs only"}]'::jsonb;
      v_exist_vcode := v_exist_vcode + 1;
    END IF;

    -- Derive Open vs Pipeline from applicant fields
    v_has_app := (v_app_last IS NOT NULL OR v_app_first IS NOT NULL);
    v_tab := CASE WHEN v_has_app THEN 'pipeline' ELSE 'open' END;

    -- ── Cross-account active applicant duplicate precheck (OHM2026_1150) ──
    -- Only applies to Pipeline rows. Requires a complete identity
    -- (last + first + contact); incomplete identity skips the guard,
    -- matching the behaviour of trg_assert_applicant_no_cross_account_active.
    -- Active-status logic is delegated to the existing helper function —
    -- it is NOT redefined here.
    IF v_has_app
       AND v_app_last  IS NOT NULL
       AND v_app_first IS NOT NULL
       AND v_contact   IS NOT NULL THEN

      -- OHM2026_1151: also resolve group name and applicant status
      -- for enriched conflict messaging. Group path:
      --   vacancies.account_id → accounts.group_id → groups.group_name
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
          -- OHM2026_1151: enriched conflict message with group + account + status
          'msg',       'Applicant has an active application under ' ||
                       v_conflict_grp || ' - ' || v_conflict_acct || ' Account.' ||
                       CASE WHEN v_conflict_status IS NOT NULL
                            THEN chr(10) || 'Current Status: ' ||
                                 initcap(replace(v_conflict_status, '_', ' ')) || '.'
                            ELSE ''
                       END,
          -- OHM2026_1151: enriched next_step referencing actual group + account
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
  'OHM2026_1135 dry-run validation — updated OHM2026_1150 to add '
  'cross-account active applicant duplicate precheck for Pipeline rows. '
  'OHM2026_1151: blocked_rows > 0 forces validation_failed (never pending_approval); '
  'conflict msg enriched with group name, account name, and current applicant status. '
  'Identity = last+first+contact; active status via fn_is_active_vacancy_applicant_status. '
  'DB trigger trg_assert_applicant_no_cross_account_active remains the final safety net. '
  'RBAC: Encoder / Head Admin / Super Admin.';


-- ============================================================
-- §3  Replace get_vacancy_import_batches to surface new column
-- ============================================================
-- Adds cross_account_applicant_count to the RETURNS TABLE and SELECT.
-- All other columns and JOIN logic are identical to the OHM2026_1140 version.

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
  rollback_applicants_count     integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
  SELECT
    b.id, b.file_name, b.status,
    b.selected_group_id, b.selected_account_id,
    g.group_name, a.account_name,
    b.uploaded_by, b.uploaded_role, b.created_at AS uploaded_at,
    b.approved_by,
    COALESCE(ap.full_name,  ap.email,  b.approved_by::text),
    b.approved_at,
    b.rejected_by,
    COALESCE(rp.full_name,  rp.email,  b.rejected_by::text),
    b.rejected_at,
    b.rejection_reason, b.rejection_reason_code, b.rejection_reason_note,
    b.commit_error_detail,
    b.total_rows, b.valid_rows, b.flagged_rows, b.skipped_rows, b.blocked_rows,
    b.open_count, b.pipeline_count, b.duplicate_vcode_count,
    b.existing_vcode_count, b.context_mismatch_count,
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
    b.rollback_applicants_count
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
$func$;

REVOKE ALL ON FUNCTION public.get_vacancy_import_batches(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_vacancy_import_batches(text) TO authenticated;

COMMENT ON FUNCTION public.get_vacancy_import_batches(text) IS
  'Import Vacancy batches listing — adds cross_account_applicant_count (OHM2026_1150). '
  'Includes reason codes/notes, approval escalation timestamps, and rollback reason codes.';


-- ============================================================
-- Validation SQL (run manually after apply)
-- ============================================================
-- 1. Confirm new column exists:
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'vacancy_import_batches'
--      AND column_name = 'cross_account_applicant_count';
--
-- 2. Confirm new RPC includes the column:
--    SELECT proname FROM pg_proc WHERE proname = 'submit_vacancy_import';
--
-- 3. Functional test — Pipeline row with a cross-account active applicant
--    should produce validation_status = 'blocked' and the validation_errors
--    entry should include field='APPLICANT' and a next_step key.
--
-- 4. Open rows (no APPLICANT_LAST_NAME / APPLICANT_FIRST_NAME) must NOT
--    be affected by the precheck.
--
-- 5. Same-account Pipeline rows must NOT be blocked by the precheck.
--
-- 6. DB trigger trg_assert_applicant_no_cross_account_active must still
--    fire at commit time (final safety net — unchanged).
-- ============================================================
