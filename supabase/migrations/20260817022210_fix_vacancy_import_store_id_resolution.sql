-- ============================================================
-- ohm#5wq2n9tv — Fix: import-created vacancies.store_id IS NULL
-- Migration: 20260817022210_fix_vacancy_import_store_id_resolution.sql
-- ============================================================
-- Root Cause
-- ----------
-- `approve_vacancy_import()` never populated `vacancies.store_id` on
-- either the fresh-INSERT or the restore-in-place UPDATE path — it only
-- carried free-text `store_name`/`chain`/`province`/`area_city` from the
-- import row. Every Vacancy-Import-created row therefore committed with
-- `store_id = NULL` (confirmed 100% of live rows on both environments,
-- see docs/state/vacancy_state.md "AUDIT" entry, ohm#5wq2n9tv).
--
-- `fn_trg_auto_create_vacancy_slot()` already has a `stores.vcode`
-- fallback (ohm#9x4p2k7q) for when `NEW.store_id IS NULL`, but that
-- fallback was starved of a real match: only 6/109 staging rows (6/106
-- prod) have a `stores.vcode` that equals the vacancy's own vcode.
--
-- Fix (approved plan, ohm#5wq2n9tv)
-- ----------------------------------
-- 1. `approve_vacancy_import()`: resolve `store_id` once per row, in
--    both the fresh-INSERT and restore-in-place UPDATE branches, using
--    only fields the import payload actually carries:
--      a) exact `stores.vcode` match (case-insensitive), status='active'
--      b) else account_id + exact store_name match (case/trim-insensitive),
--         ONLY when it resolves to exactly one store — ambiguous matches
--         (e.g. two active "ORTIGAS" stores under the same account,
--         confirmed live) are left NULL rather than guessed.
--      c) else NULL. The row still commits either way — this is
--         additive-only, no existing column, applicant-creation, or
--         exception path is touched.
--
-- 2. `fn_trg_auto_create_vacancy_slot()`: after its own store_id
--    resolution (NEW.store_id, else stores.vcode fallback) still comes
--    up NULL, write one `audit_logs` row (module='vacancies',
--    action='UPDATE', new_data.event='store_id_unresolved') so the gap
--    is visible/reportable instead of silently rediscovered. No RAISE —
--    live data shows ~82-90% of import rows have no matching `stores`
--    row at all (genuinely new, not-yet-registered stores), so hard-
--    failing commit on unresolved store_id would break the import
--    feature for the majority case, not guard an edge case.
--
-- Historical NULL rows (~215 across both environments) are NOT touched
-- by this migration — see the separate backfill migration
-- (20260817022300_backfill_vacancy_store_id_null_import_rows.sql).
--
-- Both function bodies below are CREATE OR REPLACE; every other line is
-- byte-identical to the live staging body captured via
-- pg_get_functiondef() during this prompt's diagnostics pass.
-- ============================================================

CREATE OR REPLACE FUNCTION public.approve_vacancy_import(p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- ohm#5wq2n9tv: store_id resolution
  v_store_id          uuid;
  v_store_match_count int;
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

    -- ohm#5wq2n9tv: resolve store_id for this row.
    -- Priority: (a) exact stores.vcode match, (b) account_id + exact
    -- store_name match ONLY if unique, (c) NULL. Never guess on
    -- ambiguity (confirmed live: duplicate active store names within
    -- the same account, e.g. two "ORTIGAS" stores).
    v_store_id := NULL;

    SELECT s.id INTO v_store_id
      FROM public.stores s
     WHERE upper(s.vcode) = upper(v_r.vcode)
       AND s.status = 'active';

    IF v_store_id IS NULL THEN
      SELECT count(*), min(s.id) INTO v_store_match_count, v_store_id
        FROM public.stores s
       WHERE s.account_id = v_batch.selected_account_id
         AND lower(btrim(s.store_name)) = lower(btrim(v_r.store_name))
         AND s.status = 'active';

      IF v_store_match_count <> 1 THEN
        v_store_id := NULL;
      END IF;
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
             store_id                       = v_store_id,
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
        chain, province, store_name, area_city, store_id,
        employment_type, request_type, vacancy_type,
        vacant_date, target_fill_date,
        required_headcount, has_penalty,
        hrco_name, hrco_mobile,
        source, source_vacancy_import_batch_id,
        created_by, created_by_user_id, is_archived, has_pending_closure
      ) VALUES (
        v_r.vcode, v_acct_name, v_r.position, 'Open',
        v_batch.selected_account_id, v_batch.selected_group_id,
        v_r.chain, v_r.province, v_r.store_name, v_r.city, v_store_id,
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
END$function$;

CREATE OR REPLACE FUNCTION public.fn_trg_auto_create_vacancy_slot()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_required_hc  int;
  v_max_ordinal  int;
  v_slot_id      uuid;
  v_store_id     uuid;
  v_ordinal      int;
  v_slot_status  text;
  v_aging_ts     timestamptz;
  v_emp_type     text;
BEGIN
  -- Only fire for non-pool, non-deleted, non-roving, VCODE-bearing vacancies
  -- that have affects_required_hc = true (or NULL, which defaults to true).
  IF COALESCE(NEW.is_pool_vacancy, false)       = true  THEN RETURN NEW; END IF;
  IF NEW.deleted_at IS NOT NULL                          THEN RETURN NEW; END IF;
  IF NEW.vcode IS NULL                                   THEN RETURN NEW; END IF;
  IF COALESCE(NEW.affects_required_hc, true)    = false THEN RETURN NEW; END IF;

  -- Only fire when the vacancy is entering or staying at Open/Pipeline
  IF lower(NEW.status) NOT IN ('open', 'pipeline') THEN RETURN NEW; END IF;

  -- On UPDATE: skip if status did not change to/from an open state
  -- (avoids re-firing on unrelated column updates when status is already Open)
  IF TG_OP = 'UPDATE' THEN
    IF lower(OLD.status) = lower(NEW.status) THEN
      -- Status unchanged — only re-evaluate if required_headcount increased
      IF COALESCE(NEW.required_headcount, 1) <= COALESCE(OLD.required_headcount, 1) THEN
        RETURN NEW;
      END IF;
    END IF;
  END IF;

  v_required_hc := GREATEST(COALESCE(NEW.required_headcount, 1), 1);
  v_slot_status  := CASE
                      WHEN lower(NEW.status) = 'pipeline' THEN 'pipeline'
                      ELSE 'open'
                    END;
  v_aging_ts     := COALESCE(NEW.vacant_date::timestamptz, now());
  v_emp_type     := COALESCE(NEW.employment_type, 'stationary');

  -- Resolve store_id, prioritizing NEW.store_id (fix: ohm#9x4p2k7q)
  -- Previously only did VCode lookup, causing NULL store_id for new stores
  -- where stores.vcode had not yet been set.
  IF NEW.store_id IS NOT NULL THEN
    v_store_id := NEW.store_id;
  ELSE
    SELECT s.id INTO v_store_id
    FROM public.stores s
    WHERE upper(s.vcode) = upper(NEW.vcode)
      AND s.status = 'active'
    ORDER BY s.created_at
    LIMIT 1;
  END IF;

  -- ohm#5wq2n9tv: store_id is still unresolved after both attempts above.
  -- Do NOT raise — live data shows the large majority of import-created
  -- vacancies reference stores not yet registered in `stores`, so hard-
  -- failing here would block commit for the majority case, not an edge
  -- case. Flag it instead so the gap is visible/reportable.
  IF v_store_id IS NULL THEN
    INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
    VALUES (
      public.get_current_profile_id(),
      'vacancies',
      'UPDATE',
      NEW.id,
      jsonb_build_object('event', 'store_id_unresolved', 'vcode', NEW.vcode)
    );
  END IF;

  -- Determine how many slots already exist for this VCODE
  SELECT COALESCE(MAX(ps.slot_ordinal), 0) INTO v_max_ordinal
  FROM public.plantilla_slots ps
  WHERE ps.legacy_vcode = NEW.vcode;

  -- Create only the missing ordinals (v_max_ordinal+1 .. required_hc)
  FOR v_ordinal IN (v_max_ordinal + 1) .. v_required_hc LOOP
    -- Idempotency guard
    IF EXISTS (
      SELECT 1 FROM public.plantilla_slots ps2
      WHERE ps2.legacy_vcode = NEW.vcode
        AND ps2.slot_ordinal = v_ordinal
    ) THEN
      CONTINUE;
    END IF;

    INSERT INTO public.plantilla_slots (
      store_id,
      account_id,
      group_id,
      position,
      employment_type,
      is_roving,
      slot_status,
      slot_ordinal,
      legacy_vcode,
      source_hc_request_id,
      created_at,
      updated_at
    ) VALUES (
      v_store_id,
      NEW.account_id,
      NEW.group_id,
      COALESCE(NEW.position, ''),
      v_emp_type,
      false,
      v_slot_status,
      v_ordinal::smallint,
      NEW.vcode,
      NEW.source_headcount_request_id,
      now(),
      now()
    )
    RETURNING id INTO v_slot_id;

    INSERT INTO public.slot_history (
      slot_id,
      account_id,
      action_type,
      old_value,
      new_value,
      reason_code,
      performed_by,
      remarks,
      created_at
    ) VALUES (
      v_slot_id,
      NEW.account_id,
      'status_change',
      NULL,
      v_slot_status,
      NULL,
      public.get_current_profile_id(),
      'Auto-created by fn_trg_auto_create_vacancy_slot on vacancy ' || NEW.vcode,
      v_aging_ts
    );
  END LOOP;

  RETURN NEW;
END$function$;
