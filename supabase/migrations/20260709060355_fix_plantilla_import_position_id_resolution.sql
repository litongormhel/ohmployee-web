-- ============================================================================
-- Fix: approve_plantilla_import_batch never resolves position_id from
-- position (text) via the positions table -- every baseline import commits
-- plantilla.position_id = NULL regardless of a valid POSITION column value.
-- Migration: 20260709060355_fix_plantilla_import_position_id_resolution.sql
-- Task: ohm#4dh6y1sc (BUG 1a -- import path only; see handoff for BUG 1b
-- backfill status, paused pending user decision)
-- ============================================================================
-- PROBLEM:
--   approve_plantilla_import_batch()'s Phase B INSERT INTO public.plantilla
--   column list never included position_id -- only the free-text `position`
--   column is written. No FK-resolution step from position (text) to
--   positions.id exists anywhere in the baseline import commit path. This is
--   the root cause of every Active/Stationary plantilla row on staging with
--   position_id NULL despite a populated `position` text value -- and the
--   proximate cause of the 20260708220000 hard position_id guard in
--   fn_plantilla_separation_to_vacancy() blocking separation for those rows.
--
-- FIX (forward-only, import path only -- does not touch existing rows):
--   Resolve position_id via case-insensitive/trimmed match against
--   public.positions.position_name (is_active = true) once per employee
--   record, immediately before the INSERT/UPDATE branches in the Phase B
--   employee loop. Applied uniformly across all 3 write paths (new-employee
--   INSERT, inactive/rejected-deactivation reconcile UPDATE, normal
--   existing-employee UPDATE) -- fill-if-blank convention (COALESCE) on the
--   two UPDATE paths, matching every other optional enrichment column.
--
--   POSITION remains an OPTIONAL column at submit time (confirmed via
--   submit_plantilla_baseline_import -- POSITION is never in the required-
--   field blocking list). Blank/absent POSITION text is therefore left
--   unresolved (position_id stays NULL, unchanged behavior) -- this fix does
--   not make POSITION mandatory, that is a separate, out-of-scope decision.
--
--   When POSITION text IS present but does not match any active row in
--   positions.position_name, the import now FAILS FAST at commit time
--   (RAISE EXCEPTION, ERRCODE 23503) instead of silently committing a NULL
--   position_id that only surfaces as a blocking error much later, at
--   separation time. This matches this task's explicit instruction to prefer
--   fail-fast over silent-null-with-warning.
--
-- NOT DONE (explicitly out of scope, flagged separately):
--   Backfilling position_id on the 334 pre-existing Active/non-Roving
--   plantilla rows already NULL on staging. Live investigation found only
--   ~41 of those 334 rows have position text that cleanly resolves via
--   case-insensitive/trimmed match; 263 have no position text at all
--   (nothing to resolve); ~30 have position text that does not match any
--   row in positions.position_name (e.g. "WAREHOUSE SUPPORT CREW 3",
--   "COOP ASSISTANT SUPERVISOR" -- not typos, simply absent from the
--   Position Master table). Per this task's own instruction ("if any rows
--   have a position text that does NOT cleanly resolve... STOP and report
--   the exact unresolved rows back to me before proceeding -- do not guess
--   or force a match"), the backfill is paused pending explicit user
--   direction on how to handle the blank and unmatched rows -- see
--   docs/state/plantilla_state.md and .ai/handoff.md for the full report.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.approve_plantilla_import_batch(p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '300000'
AS $function$
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
  v_date_hired_parsed  date;
  v_deployment_type    text;
  v_area_val           text;
  v_has_penalty        boolean;

  -- ohm#7c2f9a1e: normalised middle name for v_emp_name builder
  v_middle_norm        text;

  -- ohm#4dh6y1sc: position_id FK resolution (BUG 1a)
  v_position_id        uuid;

  -- Commit counts
  v_committable int;

  -- VCODE resolution guard
  v_unresolved_vcode text;

  -- Humanised error
  v_err_state text;
  v_err_msg   text;
  v_err_out   text;

  -- OHM2026_0071: Inactive reconcile path (preserved; unreachable for new batches after OHM2026_0083)
  v_inactive_id      uuid;
  v_deactivated_id   uuid;

  -- OHM2026_0071: Slot occupancy wire
  v_slot_id          uuid;
  v_slot_vcode       text;
  v_slot_result      jsonb;
  v_slot_ordinal     int;
  v_slot_store_id    uuid;

  -- OHM2026_0079: Defensive revalidation
  v_reval_emp    text;
  v_reval_vcode  text;

BEGIN
  -- Auth
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- Lock + state check
  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  -- Pre-commit guard
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

  -- Temp store commit map
  DROP TABLE IF EXISTS _pib_store_map;
  CREATE TEMP TABLE _pib_store_map (
    vcode    text,
    store_id uuid,
    is_new   boolean
  ) ON COMMIT DROP;

  -- Inner exception block -- all commit DML is atomic
  BEGIN

    -- OHM2026_0079 + OHM2026_0083: Defensive revalidation
    -- Re-run the same conflict classification as submit_plantilla_baseline_import.
    -- Catches state changes that occurred between Review Import and Approve.

    -- Check 1 (OHM2026_0079): Active non-rollback-safe plantilla employee
    SELECT pir.employee_no INTO v_reval_emp
      FROM public.plantilla_import_rows pir
     WHERE pir.batch_id = p_batch_id
       AND pir.validation_status IN ('valid','flagged')
       AND pir.employee_no IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.plantilla p
          WHERE p.employee_no = pir.employee_no
            AND p.is_deleted = false
            AND COALESCE(p.is_archived, false) = false
            AND p.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
            AND NOT EXISTS (
              SELECT 1 FROM public.plantilla_import_batches pib2
               WHERE pib2.id = p.source_baseline_import_batch_id
                 AND pib2.status = 'rolled_back'
                 AND pib2.rolled_back_at IS NOT NULL
            )
       )
     LIMIT 1;

    IF v_reval_emp IS NOT NULL THEN
      RAISE EXCEPTION
        'REVALIDATION_FAILED: employee_no % is now active in plantilla. '
        'Re-submit this batch so Review Import can reclassify the conflict.',
        v_reval_emp
        USING ERRCODE = '55000';
    END IF;

    -- Check 2 (OHM2026_0079): Archived non-rollback-safe VCode
    SELECT pir.vcode INTO v_reval_vcode
      FROM public.plantilla_import_rows pir
     WHERE pir.batch_id = p_batch_id
       AND pir.validation_status IN ('valid','flagged')
       AND pir.vcode IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.vacancies vv
          WHERE upper(trim(vv.vcode)) = pir.vcode
            AND (
              COALESCE(vv.is_archived, false) = true
              OR vv.status = 'Archived'
              OR (
                vv.deleted_at IS NOT NULL
                AND NOT (
                  vv.source_vacancy_import_batch_id IS NOT NULL
                  AND EXISTS (
                    SELECT 1 FROM public.vacancy_import_batches vib2
                     WHERE vib2.id = vv.source_vacancy_import_batch_id
                       AND vib2.rollback_status = 'completed'
                  )
                )
              )
            )
       )
     LIMIT 1;

    IF v_reval_vcode IS NOT NULL THEN
      RAISE EXCEPTION
        'REVALIDATION_FAILED: VCode % is now archived or non-reusable. '
        'Re-submit this batch so Review Import can reclassify the conflict.',
        v_reval_vcode
        USING ERRCODE = '55000';
    END IF;

    -- Check 3 (OHM2026_0083): Inactive/Rejected-Deactivation plantilla employee
    -- in valid/flagged rows. Catches in-flight batches submitted before this
    -- migration where such rows were flagged (reconcile path) rather than blocked.
    v_reval_emp := NULL;
    SELECT pir.employee_no INTO v_reval_emp
      FROM public.plantilla_import_rows pir
     WHERE pir.batch_id = p_batch_id
       AND pir.validation_status IN ('valid','flagged')
       AND pir.employee_no IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.plantilla p
          WHERE p.employee_no = pir.employee_no
            AND p.is_deleted = false
            AND COALESCE(p.is_archived, false) = false
            AND p.status IN ('Inactive', 'Rejected Deactivation')
       )
     LIMIT 1;

    IF v_reval_emp IS NOT NULL THEN
      RAISE EXCEPTION
        'REVALIDATION_FAILED: employee_no % has an inactive plantilla record. '
        'Cannot import because matching employee is inactive/archived. '
        'Restore/reactivate first or use a valid active record.',
        v_reval_emp
        USING ERRCODE = '55000';
    END IF;
    -- End defensive revalidation

    -- Phase A: Store upsert
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

    -- Post-Phase-A: VCODE resolution guard (OHM2026_1144)
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
      RAISE EXCEPTION 'STORE_RESOLUTION_FAILED: VCODE % not resolved after store upsert -- cannot commit plantilla rows',
        v_unresolved_vcode
        USING ERRCODE = '23503';
    END IF;

    -- Phase B: Employee / plantilla upsert
    FOR v_emp_rec IN
      SELECT
        employee_no,
        count(DISTINCT vcode)                                                       AS store_count,
        (array_agg(last_name   ORDER BY row_number))[1]                            AS last_name,
        (array_agg(first_name  ORDER BY row_number))[1]                            AS first_name,
        -- ohm#7c2f9a1e: FILTER (WHERE middle_name IS NOT NULL) added so that a
        -- roving employee whose earliest row has middle_name = NULL does not
        -- mask the real middle name carried by a later row. Matches the pattern
        -- already used for every other nullable enrichment column below.
        (array_agg(middle_name ORDER BY row_number)
           FILTER (WHERE middle_name IS NOT NULL))[1]                              AS middle_name,
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
        (array_agg(date_hired_raw    ORDER BY row_number)
           FILTER (WHERE date_hired_raw IS NOT NULL))[1]                           AS date_hired_raw,
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
           FILTER (WHERE coordinator_raw IS NOT NULL))[1]                          AS coordinator_raw,
        (array_agg(resolved_hrco_user_id ORDER BY row_number)
           FILTER (WHERE resolved_hrco_user_id IS NOT NULL))[1]                    AS resolved_hrco_user_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid','flagged')
         AND employee_no IS NOT NULL
       GROUP BY employee_no
    LOOP
      v_employees_done := v_employees_done + 1;
      v_store_cnt := v_emp_rec.store_count;
      v_filled    := round(1.0 / GREATEST(v_store_cnt, 1), 4);

      -- ohm#7c2f9a1e: Defensive middle-name normaliser.
      -- Exclude "NA" / "N/A" sentinel strings (same guard as the active-employee
      -- conflict name display in submit_plantilla_baseline_import). NULLIF
      -- strips blank; upper-trim comparison handles case variations.
      v_middle_norm := NULLIF(trim(COALESCE(v_emp_rec.middle_name, '')), '');
      IF upper(COALESCE(v_middle_norm, '')) IN ('NA', 'N/A', 'N.A.', 'N.A') THEN
        v_middle_norm := NULL;
      END IF;

      -- Build employee_name: "LAST, FIRST [MIDDLE]"
      -- Middle name is space-separated from first name when present.
      v_emp_name := trim(COALESCE(v_emp_rec.last_name, ''))
                    || ', '
                    || trim(COALESCE(v_emp_rec.first_name, ''))
                    || CASE
                         WHEN v_middle_norm IS NOT NULL
                         THEN ' ' || trim(v_middle_norm)
                         ELSE ''
                       END;

      v_deployment_type := CASE
        WHEN lower(COALESCE(v_emp_rec.employment_type_raw,'')) = 'stationary' THEN 'Stationary'
        WHEN lower(COALESCE(v_emp_rec.employment_type_raw,'')) = 'roving'     THEN 'Roving'
        ELSE NULLIF(trim(COALESCE(v_emp_rec.employment_type_raw,'')), '')
      END;

      v_area_val := NULLIF(trim(COALESCE(
        v_emp_rec.area_city,
        v_emp_rec.area_province,
        ''
      )), '');

      v_has_penalty := CASE
        WHEN lower(COALESCE(v_emp_rec.with_penalty_raw_agg,'')) IN ('yes','y','true','1')  THEN true
        WHEN lower(COALESCE(v_emp_rec.with_penalty_raw_agg,'')) IN ('no','n','false','0') THEN false
        ELSE NULL
      END;

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

      -- ohm#c4e91a7b: DATE_HIRED already validated (required + valid + not future)
      -- at submit time. Defensive re-parse only -- failure here should be
      -- unreachable for any row that made it to valid/flagged status.
      v_date_hired_parsed := NULL;
      BEGIN
        v_date_hired_parsed := nullif(trim(coalesce(v_emp_rec.date_hired_raw, '')), '')::date;
      EXCEPTION WHEN OTHERS THEN
        v_date_hired_parsed := NULL;
      END;

      -- ohm#4dh6y1sc (BUG 1a): resolve position_id from position (text) via
      -- the positions table. POSITION stays optional -- blank/absent text
      -- leaves v_position_id NULL, unchanged from prior behavior. Non-blank
      -- text that does not match any active position is a fail-fast error,
      -- per this task's explicit "prefer fail-fast" instruction, rather than
      -- silently committing another unresolvable position_id NULL row.
      v_position_id := NULL;
      IF NULLIF(trim(COALESCE(v_emp_rec.position, '')), '') IS NOT NULL THEN
        SELECT pos.id INTO v_position_id
          FROM public.positions pos
         WHERE lower(trim(pos.position_name)) = lower(trim(v_emp_rec.position))
           AND COALESCE(pos.is_active, true) = true
         LIMIT 1;

        IF v_position_id IS NULL THEN
          RAISE EXCEPTION
            'POSITION_NOT_FOUND: position "%" (employee_no %) does not match any active row in positions.position_name -- add it to Position Master before importing',
            v_emp_rec.position, v_emp_rec.employee_no
            USING ERRCODE = '23503';
        END IF;
      END IF;
      -- End ohm#4dh6y1sc position_id resolution

      -- OHM2026_0071: Multi-step plantilla lookup
      -- Step 1: Active / On Leave / Pending Deactivation  (existing path)
      v_plantilla_id := NULL;
      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no
         AND is_deleted = false
         AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
       LIMIT 1;

      -- Step 2 (OHM2026_0071): Inactive / Rejected Deactivation  -- reconcile path
      -- NOTE (OHM2026_0083): New batches will never reach this path because
      -- inactive employees are now BLOCKED at review time. This branch is
      -- preserved for data-integrity safety only. Defensive revalidation
      -- (Check 3 above) will have already raised REVALIDATION_FAILED for any
      -- in-flight batch that has an inactive employee in valid/flagged rows.
      v_inactive_id := NULL;
      IF v_plantilla_id IS NULL THEN
        SELECT p_inactive.id INTO v_inactive_id
          FROM public.plantilla p_inactive
         WHERE p_inactive.employee_no = v_emp_rec.employee_no
           AND p_inactive.is_deleted = false
           AND p_inactive.status IN ('Inactive', 'Rejected Deactivation')
           AND NOT EXISTS (
             SELECT 1 FROM public.plantilla_import_batches pib2
              WHERE pib2.id = p_inactive.source_baseline_import_batch_id
                AND pib2.status = 'rolled_back'
                AND pib2.rolled_back_at IS NOT NULL
           )
         LIMIT 1;

        IF v_inactive_id IS NOT NULL THEN
          v_plantilla_id := v_inactive_id;
        END IF;
      END IF;

      -- Step 3 (OHM2026_0071): Deactivated guard -- skip with NOTICE, do not reactivate
      v_deactivated_id := NULL;
      IF v_plantilla_id IS NULL THEN
        SELECT id INTO v_deactivated_id
          FROM public.plantilla
         WHERE employee_no = v_emp_rec.employee_no
           AND is_deleted = false
           AND status = 'Deactivated'
         LIMIT 1;

        IF v_deactivated_id IS NOT NULL THEN
          RAISE NOTICE
            'OHM2026_0071: Skipping employee_no=% -- existing row is Deactivated (id=%). '
            'Deactivated employees cannot be reactivated via import; manual review required.',
            v_emp_rec.employee_no, v_deactivated_id;
          v_employees_done := v_employees_done - 1;
          CONTINUE;
        END IF;
      END IF;

      SELECT to_jsonb(p.*) INTO v_old_plant_snap
        FROM public.plantilla p WHERE id = v_plantilla_id;

      v_roving_id := NULL;
      IF v_store_cnt > 1 THEN
        INSERT INTO public.import_roving_groups (
          employee_no, account_id, group_id, account_name, label,
          active_store_count, filled_hc_per_store, source_import_batch_id, created_by
        ) VALUES (
          v_emp_rec.employee_no,
          v_batch.selected_account_id, v_batch.selected_group_id,
          v_acct_name, v_emp_name || ' -- Roving',
          v_store_cnt, v_filled, p_batch_id, v_actor
        ) RETURNING id INTO v_roving_id;
      END IF;

      -- OHM2026_0065B: Roving override -- if store_count > 1, deployment_type = 'Roving'
      IF v_store_cnt > 1 THEN
        v_deployment_type := 'Roving';
      END IF;

      IF v_plantilla_id IS NULL THEN
        -- New employee: INSERT plantilla master
        INSERT INTO public.plantilla (
          employee_name, employee_no, emploc_no, account, status,
          account_id, last_name, first_name, middle_name,
          roving_assignment_id, is_pool_employee,
          position, position_id, deployment_type, has_penalty, area, area_name_snapshot,
          vcode, store_id, store_name,
          date_hired,
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
          nullif(trim(coalesce(v_emp_rec.position, '')), ''), v_position_id,
          v_deployment_type,
          v_has_penalty,
          v_area_val,
          v_area_val,
          CASE WHEN v_store_cnt = 1 THEN r.vcode     ELSE NULL END,
          CASE WHEN v_store_cnt = 1 THEN sm.store_id ELSE NULL END,
          CASE WHEN v_store_cnt = 1 THEN r.store_name ELSE NULL END,
          v_date_hired_parsed,
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

      ELSIF v_inactive_id IS NOT NULL THEN
        -- OHM2026_0071: Inactive/Rejected Deactivation reconcile path
        -- NOTE (OHM2026_0083): Defensive Check 3 above prevents reaching this
        -- path for new batches. This branch remains for historical data-integrity
        -- completeness only.
        UPDATE public.plantilla
           SET status                    = 'Active',
               inactive_at              = NULL,
               inactive_by              = NULL,
               separation_status        = NULL,
               date_of_separation       = NULL,
               resignation_date         = NULL,
               inactive_visible_until   = NULL,
               employee_name            = v_emp_name,
               last_name                = v_emp_rec.last_name,
               first_name               = v_emp_rec.first_name,
               middle_name              = v_emp_rec.middle_name,
               position                 = COALESCE(
                                            NULLIF(trim(COALESCE(position, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.position, '')), '')
                                          ),
               position_id              = COALESCE(position_id, v_position_id),
               deployment_type          = COALESCE(
                                            NULLIF(trim(COALESCE(deployment_type, '')), ''),
                                            v_deployment_type
                                          ),
               has_penalty              = COALESCE(has_penalty, v_has_penalty),
               area                     = COALESCE(
                                            NULLIF(trim(COALESCE(area, '')), ''),
                                            v_area_val
                                          ),
               area_name_snapshot       = COALESCE(
                                            NULLIF(trim(COALESCE(area_name_snapshot, '')), ''),
                                            v_area_val
                                          ),
               date_hired               = COALESCE(date_hired, v_date_hired_parsed),
               civil_status             = COALESCE(
                                            NULLIF(trim(COALESCE(civil_status, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.civil_status, '')), '')
                                          ),
               daily_rate               = COALESCE(daily_rate, v_daily_rate_parsed),
               birthdate                = COALESCE(birthdate,  v_birthdate_parsed),
               contact_no               = CASE
                                            WHEN contact_no IS NOT NULL AND contact_no <> ''
                                            THEN contact_no
                                            ELSE nullif(trim(coalesce(v_emp_rec.contact_raw, '')), '')
                                          END,
               address                  = CASE
                                            WHEN address IS NOT NULL AND address <> ''
                                            THEN address
                                            ELSE nullif(trim(coalesce(v_emp_rec.address_raw, '')), '')
                                          END,
               schedule                 = COALESCE(
                                            NULLIF(trim(COALESCE(schedule, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.schedule_raw, '')), '')
                                          ),
               dayoff                   = COALESCE(
                                            NULLIF(trim(COALESCE(dayoff, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.dayoff_raw, '')), '')
                                          ),
               coordinator              = COALESCE(
                                            NULLIF(trim(COALESCE(coordinator, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.coordinator_raw, '')), '')
                                          ),
               updated_at               = now(),
               source_baseline_import_batch_id = p_batch_id
         WHERE id = v_inactive_id;

        UPDATE public.employee_deactivation_requests
           SET status     = 'Cancelled',
               updated_at = now()
         WHERE plantilla_id = v_inactive_id
           AND status IN ('Pending')
           AND is_archived = false;

        INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
        VALUES (v_uid, 'plantilla_import', 'IMPORT_REACTIVATION', v_inactive_id,
          jsonb_build_object(
            'employee_no',  v_emp_rec.employee_no,
            'previous_status', v_old_plant_snap->>'status',
            'batch_id',     p_batch_id,
            'note',         'Employee re-imported as Active; was Inactive/Rejected Deactivation'
          ));

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_inactive_id, 'reactivate', v_old_plant_snap, v_uid);

      ELSE
        -- Normal existing employee UPDATE path
        UPDATE public.plantilla
           SET employee_name    = v_emp_name,
               last_name        = v_emp_rec.last_name,
               first_name       = v_emp_rec.first_name,
               middle_name      = v_emp_rec.middle_name,
               position         = COALESCE(
                                     NULLIF(trim(COALESCE(position, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.position, '')), '')
                                   ),
               position_id      = COALESCE(position_id, v_position_id),
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
               date_hired       = COALESCE(date_hired, v_date_hired_parsed),
               civil_status     = COALESCE(
                                     NULLIF(trim(COALESCE(civil_status, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.civil_status, '')), '')
                                   ),
               daily_rate       = COALESCE(daily_rate, v_daily_rate_parsed),
               birthdate        = COALESCE(birthdate,  v_birthdate_parsed),
               contact_no       = CASE
                                    WHEN contact_no IS NOT NULL AND contact_no <> ''
                                    THEN contact_no
                                    ELSE nullif(trim(coalesce(v_emp_rec.contact_raw, '')), '')
                                  END,
               address          = CASE
                                    WHEN address IS NOT NULL AND address <> ''
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

      -- ohm#k8d2x7qf: HRCO_EMAIL import assignment. Reuses the exact deactivate-old
      -- insert-new invariant as assign_hrco_to_plantilla so "one active per employee"
      -- can never be violated from the import path either (belt-and-suspenders with
      -- the partial unique index). No-op if this employee's resolved HRCO already
      -- matches their current active assignment (re-import idempotency).
      IF v_emp_rec.resolved_hrco_user_id IS NOT NULL AND v_plantilla_id IS NOT NULL THEN
        UPDATE public.plantilla_hrco_assignments
           SET is_active = false, effective_end = now()
         WHERE plantilla_id = v_plantilla_id AND is_active
           AND hrco_user_id IS DISTINCT FROM v_emp_rec.resolved_hrco_user_id;

        IF NOT EXISTS (
          SELECT 1 FROM public.plantilla_hrco_assignments
           WHERE plantilla_id = v_plantilla_id AND is_active
             AND hrco_user_id = v_emp_rec.resolved_hrco_user_id
        ) THEN
          INSERT INTO public.plantilla_hrco_assignments (
            plantilla_id, employee_no, account_id, hrco_user_id,
            hrco_email_snapshot, hrco_name_snapshot,
            assigned_by, assignment_source, source_import_batch_id
          )
          SELECT v_plantilla_id, v_emp_rec.employee_no, v_batch.selected_account_id,
                 v_emp_rec.resolved_hrco_user_id,
                 up.email, up.full_name,
                 v_actor, 'csv_import', p_batch_id
            FROM public.users_profile up
           WHERE up.auth_user_id = v_emp_rec.resolved_hrco_user_id;
        END IF;
      END IF;
      -- End ohm#k8d2x7qf HRCO_EMAIL import assignment

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

      -- OHM2026_0071: S2 Slot occupancy wire
      IF v_store_cnt = 1 AND v_plantilla_id IS NOT NULL THEN
        BEGIN
          SELECT pir.vcode INTO v_slot_vcode
            FROM public.plantilla_import_rows pir
           WHERE pir.batch_id = p_batch_id
             AND pir.employee_no = v_emp_rec.employee_no
             AND pir.validation_status IN ('valid','flagged')
           ORDER BY pir.row_number
           LIMIT 1;

          IF v_slot_vcode IS NOT NULL THEN
            v_slot_id := NULL;

            SELECT id INTO v_slot_id
              FROM public.plantilla_slots
             WHERE current_occupant_plantilla_id = v_plantilla_id
               AND is_roving = false
             LIMIT 1;

            IF v_slot_id IS NULL THEN
              SELECT id INTO v_slot_id
                FROM public.plantilla_slots
               WHERE legacy_vcode = v_slot_vcode
                 AND is_roving    = false
               LIMIT 1;
            END IF;

            IF v_slot_id IS NOT NULL THEN
              DECLARE
                v_slot_current_status text;
              BEGIN
                SELECT slot_status INTO v_slot_current_status
                  FROM public.plantilla_slots
                 WHERE id = v_slot_id;

                IF v_slot_current_status = 'occupied'
                   AND (SELECT current_occupant_plantilla_id FROM public.plantilla_slots WHERE id = v_slot_id) = v_plantilla_id THEN
                  RAISE NOTICE
                    'OHM2026_0071 slot wire: slot_id=% already occupied by plantilla_id=% (vcode=%)',
                    v_slot_id, v_plantilla_id, v_slot_vcode;

                ELSIF v_slot_current_status = 'closed' THEN
                  RAISE NOTICE
                    'OHM2026_0071 slot wire: slot_id=% is closed, skipping occupancy wire for plantilla_id=% (vcode=%)',
                    v_slot_id, v_plantilla_id, v_slot_vcode;

                ELSE
                  SELECT public.fn_set_slot_status(v_slot_id, 'occupied', v_plantilla_id)
                    INTO v_slot_result;
                END IF;
              END;
            END IF;
          END IF;
        EXCEPTION WHEN OTHERS THEN
          GET STACKED DIAGNOSTICS v_err_state = RETURNED_SQLSTATE,
                                  v_err_msg   = MESSAGE_TEXT;
          RAISE NOTICE 'OHM2026_0071 slot wire non-fatal: employee_no=% vcode=% state=% msg=%',
            v_emp_rec.employee_no, v_slot_vcode, v_err_state, v_err_msg;
        END;
      END IF;
      -- End OHM2026_0071 slot occupancy wire

    END LOOP;

    UPDATE public.plantilla_import_batches
       SET status       = 'approved',
           approved_by  = v_uid,
           approved_at  = now(),
           updated_at   = now()
     WHERE id = p_batch_id;

  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_err_state = RETURNED_SQLSTATE,
      v_err_msg   = MESSAGE_TEXT;

    v_err_out := format('[%s] %s', v_err_state, v_err_msg);

    UPDATE public.plantilla_import_batches
       SET status             = 'commit_error',
           commit_error_detail = v_err_out,
           updated_at          = now()
     WHERE id = p_batch_id;

    RAISE;
  END;

  RETURN jsonb_build_object(
    'ok',              true,
    'batch_id',        p_batch_id,
    'stores_created',  v_stores_done,
    'employees_done',  v_employees_done,
    'allocations_done',v_alloc_done
  );
END$function$
;
