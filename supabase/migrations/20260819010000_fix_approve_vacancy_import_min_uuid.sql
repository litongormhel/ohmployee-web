-- ============================================================
-- ohm#7n5p8xqm — Fix: approve_vacancy_import() throws
-- "function min(uuid) does not exist" (BUG-06, Critical, HA role)
-- Migration: 20260819010000_fix_approve_vacancy_import_min_uuid.sql
-- ============================================================
-- Root Cause
-- ----------
-- The live body of `approve_vacancy_import()` (last replaced by
-- 20260817022210_fix_vacancy_import_store_id_resolution.sql) resolves the
-- tier-2 store fallback (account_id + store_name match, used when the
-- vacancy's vcode does not match any `stores.vcode`) with:
--
--   SELECT count(*), min(s.id) INTO v_store_match_count, v_store_id ...
--
-- `stores.id` is `uuid`. PostgreSQL has no built-in MIN()/MAX() aggregate
-- for `uuid` — this throws `function min(uuid) does not exist` (22000) for
-- every row that needs the tier-2 fallback, aborting the whole batch commit
-- via the function's `EXCEPTION WHEN others` handler.
--
-- This is a regression: the immediately-prior migration
-- (20260817000002_fix_approve_vacancy_import_store_id_resolution.sql,
-- applied earlier the same day) implemented this exact tier correctly using
-- a window function + LIMIT 1, with an explicit comment "No MIN()/aggregate
-- on uuid anywhere." The later same-day migration silently reintroduced the
-- anti-pattern while rewriting the function for the restore-in-place
-- store_id change.
--
-- Fix (approved plan, ohm#7n5p8xqm)
-- ----------------------------------
-- Replace the `count(*)/min(s.id)` aggregate with the proven window-function
-- pattern from 20260817000002: `count(*) OVER ()` inside a subquery +
-- `LIMIT 1`, using `IS DISTINCT FROM 1` (NULL-safe) instead of `<> 1` to
-- decide ambiguity. No other branch of the function is touched: tier-1
-- (stores.vcode) resolution, the restore/insert branches, applicant
-- seeding, batch finalization, and the exception handler are byte-identical
-- to the live body. `fn_trg_auto_create_vacancy_slot()` (defined in the same
-- source file as this function but a separate trigger function) is NOT
-- re-declared here — unrelated, untouched.
--
-- Regression risk: none identified. The tier-2 fallback currently fails
-- 100% of the time it's reached (hard error, not a silent wrong answer), so
-- there is no existing caller-visible behavior this could regress. This is
-- the same query shape already staging-verified in 20260817000002.
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

    -- ohm#7n5p8xqm: window-function tier-2 fallback (BUG-06 fix).
    -- Was `SELECT count(*), min(s.id) INTO ...` — min() does not exist for
    -- uuid, which threw COMMIT_FAILED on every row needing this fallback.
    -- Same pattern as 20260817000002's tier-1 resolution: count(*) OVER ()
    -- + LIMIT 1 instead of an aggregate.
    IF v_store_id IS NULL THEN
      SELECT m.id, m.match_count
        INTO v_store_id, v_store_match_count
        FROM (
          SELECT s.id, count(*) OVER () AS match_count
            FROM public.stores s
           WHERE s.account_id = v_batch.selected_account_id
             AND lower(btrim(s.store_name)) = lower(btrim(v_r.store_name))
             AND s.status = 'active'
        ) m
       LIMIT 1;

      IF v_store_match_count IS DISTINCT FROM 1 THEN
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
