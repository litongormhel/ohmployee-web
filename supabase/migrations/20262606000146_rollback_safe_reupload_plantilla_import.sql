-- ============================================================================
-- Migration: 20262606000146_rollback_safe_reupload_plantilla_import.sql
-- ADR-002 Invariant #10 Amendment: Rollback Must Not Treat As Archive Data
--
-- Problem:
--   When a Plantilla Import batch is rolled back, its created plantilla rows
--   are soft-archived (status = 'Inactive', is_archived = true).
--   Previously, re-uploading the original file (or an updated version) of that
--   rolled-back batch was erroneously hard-blocked during pre-upload validation
--   with "Employee exists in plantilla with inactive/archived status. Re-import blocked."
--   because _evaluate_plantilla_import_rows treated rolled-back rows as operational archives.
--
-- Solution:
--   1. _evaluate_plantilla_import_rows:
--      - Distinguish genuine operational inactive/archived records (e.g. from
--        actual separation, resignation, AWOL, termination, or non-rollback archive)
--        from rolled-back batch records (is_rollback = true).
--      - Genuine inactive records continue to strictly HARD BLOCK re-import
--        ("unless may dating naka archive na data na na dagdag").
--      - Rolled-back batch records are rollback-safe: they do NOT block re-upload,
--        and instead surface an informational non-blocking flag:
--        conflict_type = 'rollback_safe_employee' ("Rollback record detected — eligible for re-upload.").
--      - Exclude rolled-back batch records from db_name_conflict.
--   2. approve_plantilla_import_batch:
--      - Phase A: Re-activate archived stores under the same account & VCODE
--        (status = 'active', is_active = true, is_archived = false) preventing duplicate store rows.
--      - Phase B2: Plantilla lookup strictly restricts update targets to active
--        employees (status IN ('Active','For Deactivation','On Leave','Pending Deactivation','Floating')).
--        Rolled-back records are not updated in place; instead, a fresh active
--        plantilla record is inserted under the new batch, preserving historical
--        audit lineage for the previous rolled-back batch.
-- ============================================================================

CREATE OR REPLACE FUNCTION public._evaluate_plantilla_import_rows(
  p_group_id   uuid,
  p_account_id uuid,
  p_rows       jsonb
)
RETURNS TABLE (
  row_num               int,
  raw_row               jsonb,
  vcode                 text,
  final_store_name      text,
  mother_acct           text,
  prov                  text,
  city                  text,
  "position"            text,
  emp_no                text,
  last_name             text,
  first_name            text,
  middle_name           text,
  date_hired            text,
  civil_status          text,
  rate_raw              text,
  birthdate_raw         text,
  contact_raw           text,
  address_raw           text,
  sched_days_raw        text,
  sched_time_raw        text,
  dayoff_raw            text,
  coord_raw             text,
  hrco_email_raw        text,
  row_final_hrco_id     uuid,
  row_needs_hrco        boolean,
  resolved_store_id     uuid,
  is_new_store          boolean,
  is_existing_emp       boolean,
  is_roving             boolean,
  roving_store_count    int,
  employment_type       text,
  required_hc_raw       text,
  with_penalty_raw      text,
  validation_errors     jsonb,
  validation_flags      jsonb,
  is_dup_pair           boolean,
  validation_status     text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '60s'
AS $func$
DECLARE
  v_acct_hrco_id     uuid;
  v_resolved_hrco_id uuid;
  v_needs_hrco       boolean;
BEGIN
  SELECT hrco_user_id
    INTO v_acct_hrco_id
    FROM public.accounts WHERE id = p_account_id;

  v_resolved_hrco_id := v_acct_hrco_id;
  IF v_resolved_hrco_id IS NULL THEN
    SELECT u.id INTO v_resolved_hrco_id
      FROM public.users_profile u
     WHERE u.is_active = true
       AND u.account_id = p_account_id
       AND lower(u.role) IN ('hrco', 'hr coordinator')
     LIMIT 1;
  END IF;
  v_needs_hrco := (v_resolved_hrco_id IS NULL);

  RETURN QUERY
  WITH parsed AS MATERIALIZED (
    SELECT
      (row_number() OVER ())::int AS row_num,
      elem.value AS raw_row,
      upper(NULLIF(trim(COALESCE(elem.value->>'VCODE','')), '')) AS vcode,
      NULLIF(trim(COALESCE(elem.value->>'STORE_NAME','')), '') AS store_nm,
      NULLIF(trim(COALESCE(elem.value->>'MOTHER_ACCOUNT','')), '') AS mother_acct,
      NULLIF(trim(COALESCE(elem.value->>'AREA_PROVINCE','')), '') AS prov,
      NULLIF(trim(COALESCE(elem.value->>'AREA_CITY','')), '') AS city,
      upper(NULLIF(trim(COALESCE(elem.value->>'POSITION','')), '')) AS pos,
      upper(NULLIF(trim(COALESCE(elem.value->>'EMPLOYEE_NO','')), '')) AS emp_no,
      upper(NULLIF(trim(COALESCE(elem.value->>'LAST_NAME','')), '')) AS last_name,
      upper(NULLIF(trim(COALESCE(elem.value->>'FIRST_NAME','')), '')) AS first_name,
      upper(NULLIF(trim(COALESCE(elem.value->>'MIDDLE_NAME','')), '')) AS middle_name,
      NULLIF(trim(COALESCE(elem.value->>'DATE_HIRED','')), '') AS date_hired,
      upper(NULLIF(trim(COALESCE(elem.value->>'CIVIL_STATUS','')), '')) AS civil_status,
      NULLIF(trim(COALESCE(elem.value->>'RATE','')), '') AS rate_raw,
      NULLIF(trim(COALESCE(elem.value->>'DATE_OF_BIRTH', elem.value->>'BIRTHDATE', '')), '') AS birthdate_raw,
      NULLIF(trim(COALESCE(elem.value->>'CONTACT_NO', elem.value->>'CONTACT', '')), '') AS contact_raw,
      upper(NULLIF(trim(COALESCE(elem.value->>'ADDRESS','')), '')) AS address_raw,
      NULLIF(trim(COALESCE(elem.value->>'SCHEDULE_DAYS', elem.value->>'SCHEDULE', '')), '') AS sched_days_raw,
      NULLIF(trim(COALESCE(elem.value->>'SCHEDULE_TIME','')), '') AS sched_time_raw,
      NULLIF(trim(COALESCE(elem.value->>'DAYOFF','')), '') AS dayoff_raw,
      NULLIF(trim(COALESCE(elem.value->>'COORDINATOR','')), '') AS coord_raw,
      NULLIF(trim(COALESCE(elem.value->>'HRCO_EMAIL','')), '') AS hrco_email_raw
    FROM jsonb_array_elements(p_rows) AS elem
  ),
  vcode_conflicts AS MATERIALIZED (
    SELECT p.vcode 
    FROM parsed p
    WHERE p.vcode IS NOT NULL AND p.store_nm IS NOT NULL 
    GROUP BY p.vcode 
    HAVING count(DISTINCT upper(trim(p.store_nm))) > 1
  ),
  store_conflicts AS MATERIALIZED (
    SELECT upper(trim(p.store_nm)) AS store_upper
    FROM parsed p
    WHERE p.vcode IS NOT NULL AND p.store_nm IS NOT NULL
    GROUP BY upper(trim(p.store_nm))
    HAVING count(DISTINCT p.vcode) > 1
  ),
  emp_store_counts AS MATERIALIZED (
    SELECT p.emp_no, count(DISTINCT p.vcode) as store_cnt 
    FROM parsed p 
    WHERE p.emp_no IS NOT NULL AND p.vcode IS NOT NULL 
    GROUP BY p.emp_no
  ),
  emp_vcode_dups AS MATERIALIZED (
    SELECT sub.row_num 
    FROM (
      SELECT p.row_num, row_number() OVER (PARTITION BY p.emp_no, p.vcode ORDER BY p.row_num) as rn
      FROM parsed p
      WHERE p.emp_no IS NOT NULL AND p.vcode IS NOT NULL
    ) sub 
    WHERE sub.rn > 1
  ),
  name_emp_conflicts AS MATERIALIZED (
    SELECT
      p.last_name,
      p.first_name,
      p.middle_name,
      count(DISTINCT p.emp_no) AS distinct_emp_cnt,
      string_agg(DISTINCT p.emp_no, ', ' ORDER BY p.emp_no) AS conflicting_emp_nos
    FROM parsed p
    WHERE p.last_name IS NOT NULL
      AND p.first_name IS NOT NULL
      AND p.middle_name IS NOT NULL
      AND p.emp_no IS NOT NULL
    GROUP BY p.last_name, p.first_name, p.middle_name
    HAVING count(DISTINCT p.emp_no) > 1
  ),
  emp_agg AS MATERIALIZED (
    SELECT
      p.emp_no,
      count(DISTINCT p.last_name) AS distinct_last_name_cnt,
      count(DISTINCT p.first_name) AS distinct_first_name_cnt,
      count(DISTINCT p.middle_name) AS distinct_middle_name_cnt,
      count(DISTINCT p.date_hired) AS distinct_date_hired_cnt,
      count(p.pos) AS pos_cnt,
      count(DISTINCT p.civil_status) AS distinct_civil_status_cnt,
      count(DISTINCT p.rate_raw) AS distinct_rate_cnt,
      count(DISTINCT p.birthdate_raw) AS distinct_birthdate_cnt,
      count(DISTINCT p.contact_raw) AS distinct_contact_cnt,
      count(DISTINCT p.address_raw) AS distinct_address_cnt,
      count(DISTINCT p.dayoff_raw) AS distinct_dayoff_cnt,

      -- Coalesced values (last non-null row wins)
      (array_agg(p.last_name ORDER BY p.row_num DESC) FILTER (WHERE p.last_name IS NOT NULL))[1] AS coalesced_last_name,
      (array_agg(p.first_name ORDER BY p.row_num DESC) FILTER (WHERE p.first_name IS NOT NULL))[1] AS coalesced_first_name,
      (array_agg(p.middle_name ORDER BY p.row_num DESC) FILTER (WHERE p.middle_name IS NOT NULL))[1] AS coalesced_middle_name,
      (array_agg(p.date_hired ORDER BY p.row_num DESC) FILTER (WHERE p.date_hired IS NOT NULL))[1] AS coalesced_date_hired,
      (array_agg(p.pos ORDER BY p.row_num DESC) FILTER (WHERE p.pos IS NOT NULL))[1] AS coalesced_pos,
      (array_agg(p.civil_status ORDER BY p.row_num DESC) FILTER (WHERE p.civil_status IS NOT NULL))[1] AS coalesced_civil_status,
      (array_agg(p.rate_raw ORDER BY p.row_num DESC) FILTER (WHERE p.rate_raw IS NOT NULL))[1] AS coalesced_rate,
      (array_agg(p.birthdate_raw ORDER BY p.row_num DESC) FILTER (WHERE p.birthdate_raw IS NOT NULL))[1] AS coalesced_birthdate,
      (array_agg(p.contact_raw ORDER BY p.row_num DESC) FILTER (WHERE p.contact_raw IS NOT NULL))[1] AS coalesced_contact,
      (array_agg(p.address_raw ORDER BY p.row_num DESC) FILTER (WHERE p.address_raw IS NOT NULL))[1] AS coalesced_address,
      (array_agg(p.dayoff_raw ORDER BY p.row_num DESC) FILTER (WHERE p.dayoff_raw IS NOT NULL))[1] AS coalesced_dayoff
    FROM parsed p
    WHERE p.emp_no IS NOT NULL
    GROUP BY p.emp_no
  ),
  evaluated AS (
    SELECT
      p.row_num,
      p.raw_row,
      p.vcode,
      COALESCE(p.store_nm, p.raw_row->>'STORE_NAME') AS final_store_name,
      p.mother_acct,
      p.prov,
      p.city,
      COALESCE(p.pos, ea.coalesced_pos) AS position_val,
      p.emp_no,
      p.last_name,
      p.first_name,
      p.middle_name,
      p.date_hired,
      COALESCE(p.civil_status, ea.coalesced_civil_status) AS civil_status,
      COALESCE(p.rate_raw, ea.coalesced_rate) AS rate_raw,
      COALESCE(p.birthdate_raw, ea.coalesced_birthdate) AS birthdate_raw,
      COALESCE(p.contact_raw, ea.coalesced_contact) AS contact_raw,
      COALESCE(p.address_raw, ea.coalesced_address) AS address_raw,
      p.sched_days_raw,
      p.sched_time_raw,
      COALESCE(p.dayoff_raw, ea.coalesced_dayoff) AS dayoff_raw,
      p.coord_raw,
      p.hrco_email_raw,

      -- HRCO resolution
      COALESCE(row_hrco.id, v_resolved_hrco_id) AS row_final_hrco_id,
      (COALESCE(row_hrco.id, v_resolved_hrco_id) IS NULL AND (p.hrco_email_raw IS NULL OR trim(p.hrco_email_raw) = '')) AS row_needs_hrco,

      -- DB store resolution
      db_store.id AS resolved_store_id,
      (db_store.id IS NULL) AS is_new_store,
      (p.emp_no IS NOT NULL AND (db_plantilla.id IS NOT NULL OR db_emp.id IS NOT NULL)) AS is_existing_emp,

      -- Roving & HC
      (p.emp_no IS NOT NULL AND COALESCE(esc.store_cnt, 1) > 1) AS is_roving,
      COALESCE(esc.store_cnt, 0)::int AS roving_store_count,
      CASE 
        WHEN p.emp_no IS NOT NULL AND COALESCE(esc.store_cnt, 1) > 1 THEN 'roving'
        ELSE 'stationary'
      END AS employment_type,
      CASE 
        WHEN p.emp_no IS NOT NULL AND COALESCE(esc.store_cnt, 1) > 1 THEN trim(to_char(round(1.0 / esc.store_cnt, 2), 'FM999990.00'))
        ELSE '1.00'
      END AS required_hc_raw,

      -- With penalty
      CASE 
        WHEN COALESCE(mac.with_penalty, (lower(COALESCE(p.raw_row->>'WITH_PENALTY','')) IN ('yes','y','true','1'))) THEN 'yes'
        ELSE 'no'
      END AS with_penalty_raw,

      -- Validation errors array (Hard blocking errors)
      (
        SELECT COALESCE(jsonb_agg(err), '[]'::jsonb)
        FROM (
          -- Required Store / Slot Fields
          SELECT CASE WHEN p.vcode IS NULL THEN jsonb_build_object('field','VCODE','msg','VCODE is required') END AS err UNION ALL
          SELECT CASE WHEN p.store_nm IS NULL THEN jsonb_build_object('field','STORE_NAME','msg','STORE_NAME is required') END UNION ALL
          SELECT CASE WHEN p.mother_acct IS NULL THEN jsonb_build_object('field','MOTHER_ACCOUNT','msg','MOTHER_ACCOUNT is required') END UNION ALL
          SELECT CASE WHEN p.prov IS NULL THEN jsonb_build_object('field','AREA_PROVINCE','msg','AREA_PROVINCE is required') END UNION ALL
          SELECT CASE WHEN p.city IS NULL THEN jsonb_build_object('field','AREA_CITY','msg','AREA_CITY is required') END UNION ALL

          -- In-file Store Master Cross Conflicts
          SELECT CASE WHEN vc.vcode IS NOT NULL THEN jsonb_build_object('field','VCODE','conflict_type','in_file_vcode_conflict','msg','In-file conflict: same VCODE used with multiple distinct STORE_NAMEs') END UNION ALL
          SELECT CASE WHEN sc.store_upper IS NOT NULL THEN jsonb_build_object('field','STORE_NAME','conflict_type','in_file_store_conflict','msg','In-file conflict: same STORE_NAME assigned to multiple distinct VCODEs') END UNION ALL

          -- DB Store Master Invariants (ADR-002 Invariant #1: 1 Store Name = 1 Permanent VCODE)
          SELECT CASE WHEN db_store.id IS NOT NULL AND upper(trim(db_store.store_name)) <> upper(trim(p.store_nm)) THEN jsonb_build_object('field','VCODE','conflict_type','db_store_conflict','msg',format('DB store conflict: VCODE %s belongs to "%s", cannot reassign to "%s"', p.vcode, db_store.store_name, p.store_nm)) END UNION ALL

          -- Account / Group Store Lock
          SELECT CASE WHEN db_store.id IS NOT NULL AND db_store.account_id IS NOT NULL AND db_store.account_id <> p_account_id THEN jsonb_build_object('field','VCODE','conflict_type','cross_account_store','msg','cross-account: store already belongs to a different account') END UNION ALL
          SELECT CASE WHEN db_store.id IS NOT NULL AND db_store.group_id IS NOT NULL AND db_store.group_id <> p_group_id THEN jsonb_build_object('field','VCODE','conflict_type','cross_group_store','msg','cross-group: store already belongs to a different group') END UNION ALL

          -- Intra-file Duplicate VCode for same Employee
          SELECT CASE WHEN evd.row_num IS NOT NULL THEN jsonb_build_object('field','VCODE','conflict_type','duplicate_store_for_employee','msg',format('Duplicate row for employee %s at store %s: an employee can only be assigned once per store slot in a batch', p.emp_no, p.vcode)) END UNION ALL

          -- R2 Employee-Level Position Invariant
          SELECT CASE WHEN p.emp_no IS NOT NULL AND COALESCE(ea.pos_cnt, 0) = 0 THEN jsonb_build_object('field','POSITION','conflict_type','position_required','msg',format('POSITION is blank across all rows for EMPLOYEE_NO %s: position is mandatory', p.emp_no)) END UNION ALL

          -- R2 Intra-file Core Identity Invariants across rows of same EMPLOYEE_NO
          SELECT CASE WHEN p.emp_no IS NOT NULL AND ea.distinct_last_name_cnt > 1 THEN jsonb_build_object('field','LAST_NAME','conflict_type','core_identity_mismatch_in_batch','msg',format('Core identity mismatch across rows for EMPLOYEE_NO %s: distinct LAST_NAME values in batch', p.emp_no)) END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND ea.distinct_first_name_cnt > 1 THEN jsonb_build_object('field','FIRST_NAME','conflict_type','core_identity_mismatch_in_batch','msg',format('Core identity mismatch across rows for EMPLOYEE_NO %s: distinct FIRST_NAME values in batch', p.emp_no)) END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND ea.distinct_middle_name_cnt > 1 THEN jsonb_build_object('field','MIDDLE_NAME','conflict_type','core_identity_mismatch_in_batch','msg',format('Core identity mismatch across rows for EMPLOYEE_NO %s: distinct MIDDLE_NAME values in batch', p.emp_no)) END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND ea.distinct_date_hired_cnt > 1 THEN jsonb_build_object('field','DATE_HIRED','conflict_type','core_identity_mismatch_in_batch','msg',format('Core identity mismatch across rows for EMPLOYEE_NO %s: distinct DATE_HIRED values in batch', p.emp_no)) END UNION ALL

          -- R2 Bi-Directional Core Identity Invariant (1 Person = 1 EMPLOYEE_NO)
          SELECT CASE WHEN p.emp_no IS NOT NULL AND nec.distinct_emp_cnt > 1 THEN jsonb_build_object('field','EMPLOYEE_NO','conflict_type','duplicate_identity_distinct_emp_no','msg',format('Duplicate identity conflict across rows for "%s, %s %s": assigned multiple distinct EMPLOYEE_NO values (%s). Roving employees must share the exact same EMPLOYEE_NO.', p.last_name, p.first_name, p.middle_name, nec.conflicting_emp_nos)) END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND COALESCE(db_name_conflict.employee_no, db_emp_name_conflict.employee_no) IS NOT NULL THEN jsonb_build_object('field','EMPLOYEE_NO','conflict_type','duplicate_identity_db_mismatch','msg',format('Duplicate identity conflict against DB master: "%s, %s %s" already exists with EMPLOYEE_NO "%s"; uploaded row specifies "%s".', p.last_name, p.first_name, p.middle_name, COALESCE(db_name_conflict.employee_no, db_emp_name_conflict.employee_no), p.emp_no)) END UNION ALL

          -- Inactive Plantilla Status Lock (Rule #1 Invariant & ADR-002 Rollback Safety)
          -- Genuine inactive/separated records block re-import.
          -- Rolled-back records (is_rollback = true) are rollback-safe and NOT treated as operational archive data.
          SELECT CASE 
            WHEN p.emp_no IS NOT NULL 
             AND db_plantilla.id IS NOT NULL 
             AND db_plantilla.status IN ('Inactive','Rejected Deactivation') 
             AND NOT COALESCE(db_plantilla.is_rollback, false)
            THEN jsonb_build_object(
              'field','EMPLOYEE_NO',
              'conflict_type','inactive_or_archived_existing_record',
              'msg',format('Employee %s exists in plantilla with inactive/archived status ("%s"). Re-import blocked.', p.emp_no, db_plantilla.status)
            ) 
          END UNION ALL

          -- Cross-Account Active Employee Guard
          SELECT CASE WHEN p.emp_no IS NOT NULL AND db_plantilla.id IS NOT NULL AND db_plantilla.account_id IS NOT NULL AND db_plantilla.account_id <> p_account_id AND db_plantilla.status IN ('Active','For Deactivation','On Leave','Pending Deactivation') THEN jsonb_build_object('field','EMPLOYEE_NO','conflict_type','cross_account_employee','msg','cross-account: employee exists in active plantilla under a different account') END UNION ALL

          -- R2 DB Master Record Core Identity Match
          SELECT CASE WHEN p.emp_no IS NOT NULL AND p.last_name IS NOT NULL AND COALESCE(db_plantilla.last_name, db_emp.last_name) IS NOT NULL AND upper(trim(COALESCE(db_plantilla.last_name, db_emp.last_name))) <> p.last_name THEN jsonb_build_object('field','LAST_NAME','conflict_type','core_identity_mismatch_with_db','msg',format('Core identity mismatch against DB master record for employee %s: uploaded LAST_NAME "%s" does not match DB master "%s"', p.emp_no, p.last_name, COALESCE(db_plantilla.last_name, db_emp.last_name))) END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND p.first_name IS NOT NULL AND COALESCE(db_plantilla.first_name, db_emp.first_name) IS NOT NULL AND upper(trim(COALESCE(db_plantilla.first_name, db_emp.first_name))) <> p.first_name THEN jsonb_build_object('field','FIRST_NAME','conflict_type','core_identity_mismatch_with_db','msg',format('Core identity mismatch against DB master record for employee %s: uploaded FIRST_NAME "%s" does not match DB master "%s"', p.emp_no, p.first_name, COALESCE(db_plantilla.first_name, db_emp.first_name))) END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND p.middle_name IS NOT NULL AND COALESCE(db_plantilla.middle_name, db_emp.middle_name) IS NOT NULL AND upper(trim(COALESCE(db_plantilla.middle_name, db_emp.middle_name))) <> p.middle_name THEN jsonb_build_object('field','MIDDLE_NAME','conflict_type','core_identity_mismatch_with_db','msg',format('Core identity mismatch against DB master record for employee %s: uploaded MIDDLE_NAME "%s" does not match DB master "%s"', p.emp_no, p.middle_name, COALESCE(db_plantilla.middle_name, db_emp.middle_name))) END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND p.date_hired IS NOT NULL AND COALESCE(db_plantilla.date_hired, db_emp.date_hired) IS NOT NULL AND COALESCE(db_plantilla.date_hired, db_emp.date_hired) <> p.date_hired THEN jsonb_build_object('field','DATE_HIRED','conflict_type','core_identity_mismatch_with_db','msg',format('Core identity mismatch against DB master record for employee %s: uploaded DATE_HIRED "%s" does not match DB master "%s"', p.emp_no, p.date_hired, COALESCE(db_plantilla.date_hired, db_emp.date_hired))) END UNION ALL

          -- R3 Minimum Age Invariant (18+ as of DATE_HIRED)
          SELECT CASE 
            WHEN p.emp_no IS NOT NULL 
             AND public.safe_parse_date(COALESCE(p.birthdate_raw, ea.coalesced_birthdate)) IS NOT NULL
             AND (public.safe_parse_date(COALESCE(p.birthdate_raw, ea.coalesced_birthdate)) + INTERVAL '18 years')::date > COALESCE(public.safe_parse_date(COALESCE(p.date_hired, ea.coalesced_date_hired)), CURRENT_DATE)
            THEN jsonb_build_object(
              'field', 'DATE_OF_BIRTH',
              'conflict_type', 'underage_employee_under_18',
              'msg', format(
                'Underage employee: computed age as of DATE_HIRED (%s) is under 18 years old (DOB: %s, age: %s). Minimum legal working age is 18.',
                COALESCE(public.safe_parse_date(COALESCE(p.date_hired, ea.coalesced_date_hired))::text, CURRENT_DATE::text),
                public.safe_parse_date(COALESCE(p.birthdate_raw, ea.coalesced_birthdate))::text,
                EXTRACT(YEAR FROM age(COALESCE(public.safe_parse_date(COALESCE(p.date_hired, ea.coalesced_date_hired)), CURRENT_DATE), public.safe_parse_date(COALESCE(p.birthdate_raw, ea.coalesced_birthdate))))
              )
            )
          END
        ) sub_err WHERE err IS NOT NULL
      ) AS validation_errors,

      -- Validation flags array (Non-blocking warnings)
      (
        SELECT COALESCE(jsonb_agg(flg), '[]'::jsonb)
        FROM (
          -- Rollback-safe employee re-upload flag (ADR-002 Rollback Safety)
          SELECT CASE 
            WHEN p.emp_no IS NOT NULL 
             AND db_plantilla.id IS NOT NULL 
             AND COALESCE(db_plantilla.is_rollback, false)
             AND db_plantilla.status IN ('Inactive','Rejected Deactivation')
            THEN jsonb_build_object(
              'field','EMPLOYEE_NO',
              'flag','rollback_safe_employee',
              'conflict_type','rollback_safe_employee',
              'msg',format('Rollback record detected for employee %s — eligible for re-upload.', p.emp_no)
            ) 
          END AS flg UNION ALL

          -- R2 Demographics, Compensation & Dayoff Conflicts (Last-Row-Wins)
          SELECT CASE WHEN p.emp_no IS NOT NULL AND ea.distinct_civil_status_cnt > 1 THEN jsonb_build_object('field','CIVIL_STATUS','conflict_type','conflict_civil_status','msg',format('Row has conflicting CIVIL_STATUS for %s; applying last row value "%s"', p.emp_no, ea.coalesced_civil_status)) END AS flg UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND ea.distinct_rate_cnt > 1 THEN jsonb_build_object('field','RATE','conflict_type','conflict_rate','msg',format('Row has conflicting RATE for %s; applying last row value "%s"', p.emp_no, ea.coalesced_rate)) END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND ea.distinct_birthdate_cnt > 1 THEN jsonb_build_object('field','DATE_OF_BIRTH','conflict_type','conflict_birthdate','msg',format('Row has conflicting DATE_OF_BIRTH for %s; applying last row value "%s"', p.emp_no, ea.coalesced_birthdate)) END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND ea.distinct_contact_cnt > 1 THEN jsonb_build_object('field','CONTACT_NO','conflict_type','conflict_contact','msg',format('Row has conflicting CONTACT_NO for %s; applying last row value "%s"', p.emp_no, ea.coalesced_contact)) END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND ea.distinct_address_cnt > 1 THEN jsonb_build_object('field','ADDRESS','conflict_type','conflict_address','msg',format('Row has conflicting ADDRESS for %s; applying last row value "%s"', p.emp_no, ea.coalesced_address)) END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND ea.distinct_dayoff_cnt > 1 THEN jsonb_build_object('field','DAYOFF','conflict_type','conflict_dayoff','msg',format('Row has conflicting DAYOFF for %s; applying last row value "%s"', p.emp_no, ea.coalesced_dayoff)) END UNION ALL

          -- Missing HRCO Warning
          SELECT CASE WHEN row_hrco.id IS NULL AND v_resolved_hrco_id IS NULL AND (p.hrco_email_raw IS NULL OR trim(p.hrco_email_raw) = '') THEN jsonb_build_object('field','HRCO_EMAIL','conflict_type','missing_hrco','msg','No account-level HRCO assigned and HRCO_EMAIL column is blank') END UNION ALL

          -- Schedule / Rest Day Overlap Warning
          SELECT CASE WHEN p.dayoff_raw IS NOT NULL AND p.sched_days_raw IS NOT NULL AND position(upper(trim(p.dayoff_raw)) IN upper(trim(p.sched_days_raw))) > 0 THEN jsonb_build_object('field','SCHEDULE_DAYS','conflict_type','schedule_rest_day_overlap','msg',format('SCHEDULE_DAYS (%s) overlaps with DAYOFF (%s); duty days should exclude designated rest days', p.sched_days_raw, p.dayoff_raw)) END UNION ALL

          -- Over 20 stores roving warning
          SELECT CASE WHEN p.emp_no IS NOT NULL AND COALESCE(esc.store_cnt, 0) > 20 THEN jsonb_build_object('field','EMPLOYEE_NO','conflict_type','over_20_stores','msg',format('Employee %s assigned to %s stores (exceeds standard 20-store guideline)', p.emp_no, esc.store_cnt)) END
        ) sub_flg WHERE flg IS NOT NULL
      ) AS validation_flags,

      -- Duplicate pair within batch (identical store + emp_no already seen)
      (evd.row_num IS NOT NULL) AS is_dup_pair

    FROM parsed p
    LEFT JOIN vcode_conflicts vc ON vc.vcode = p.vcode
    LEFT JOIN store_conflicts sc ON sc.store_upper = upper(trim(p.store_nm))
    LEFT JOIN emp_store_counts esc ON esc.emp_no = p.emp_no
    LEFT JOIN emp_vcode_dups evd ON evd.row_num = p.row_num
    LEFT JOIN emp_agg ea ON ea.emp_no = p.emp_no
    LEFT JOIN name_emp_conflicts nec ON nec.last_name = p.last_name AND nec.first_name = p.first_name AND nec.middle_name = p.middle_name
    LEFT JOIN LATERAL (
      SELECT s.id, s.account_id, s.group_id, s.store_name 
      FROM public.stores s 
      WHERE upper(s.vcode) = p.vcode AND s.status = 'active' 
      ORDER BY s.created_at LIMIT 1
    ) db_store ON true
    LEFT JOIN public.mother_account_configs mac ON upper(trim(mac.mother_account)) = upper(trim(p.mother_acct))
    LEFT JOIN LATERAL (
      SELECT
        pl.id,
        pl.account_id,
        pl.status,
        upper(trim(pl.last_name)) AS last_name,
        upper(trim(pl.first_name)) AS first_name,
        upper(trim(pl.middle_name)) AS middle_name,
        pl.date_hired::text AS date_hired,
        (
          (pl.source_baseline_import_batch_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.plantilla_import_batches pib
            WHERE pib.id = pl.source_baseline_import_batch_id
              AND pib.status = 'rolled_back'
          ))
          OR COALESCE(pl.archive_reason, '') ILIKE '%rollback%'
        ) AS is_rollback
      FROM public.plantilla pl 
      WHERE pl.employee_no = p.emp_no 
        AND pl.is_deleted = false 
      ORDER BY 
        CASE 
          WHEN pl.status IN ('Active','For Deactivation','On Leave','Pending Deactivation') THEN 1 
          WHEN pl.status IN ('Inactive','Rejected Deactivation') AND NOT (
            (pl.source_baseline_import_batch_id IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.plantilla_import_batches pib
              WHERE pib.id = pl.source_baseline_import_batch_id
                AND pib.status = 'rolled_back'
            ))
            OR COALESCE(pl.archive_reason, '') ILIKE '%rollback%'
          ) THEN 2 
          WHEN pl.status IN ('Inactive','Rejected Deactivation') THEN 3 
          ELSE 4 
        END,
        pl.created_at DESC 
      LIMIT 1
    ) db_plantilla ON (p.emp_no IS NOT NULL)
    LEFT JOIN LATERAL (
      SELECT
        pl.id,
        pl.employee_no
      FROM public.plantilla pl 
      WHERE pl.is_deleted = false 
        AND pl.employee_no IS NOT NULL 
        AND upper(trim(pl.last_name)) = p.last_name 
        AND upper(trim(pl.first_name)) = p.first_name 
        AND upper(trim(pl.middle_name)) = p.middle_name 
        AND pl.employee_no <> p.emp_no 
        AND NOT (
          (pl.source_baseline_import_batch_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.plantilla_import_batches pib
            WHERE pib.id = pl.source_baseline_import_batch_id
              AND pib.status = 'rolled_back'
          ))
          OR COALESCE(pl.archive_reason, '') ILIKE '%rollback%'
        )
      LIMIT 1
    ) db_name_conflict ON (p.emp_no IS NOT NULL AND p.last_name IS NOT NULL AND p.first_name IS NOT NULL AND p.middle_name IS NOT NULL)
    LEFT JOIN LATERAL (
      SELECT
        e.id,
        upper(trim(e.last_name)) AS last_name,
        upper(trim(e.first_name)) AS first_name,
        upper(trim(e.middle_name)) AS middle_name,
        e.date_hired::text AS date_hired
      FROM public.employees e
      WHERE e.employee_no = p.emp_no
      LIMIT 1
    ) db_emp ON (p.emp_no IS NOT NULL)
    LEFT JOIN LATERAL (
      SELECT
        e.id,
        e.employee_no
      FROM public.employees e 
      WHERE e.employee_no IS NOT NULL 
        AND upper(trim(e.last_name)) = p.last_name 
        AND upper(trim(e.first_name)) = p.first_name 
        AND upper(trim(e.middle_name)) = p.middle_name 
        AND e.employee_no <> p.emp_no 
      LIMIT 1
    ) db_emp_name_conflict ON (p.emp_no IS NOT NULL AND p.last_name IS NOT NULL AND p.first_name IS NOT NULL AND p.middle_name IS NOT NULL)
    LEFT JOIN LATERAL (
      SELECT u.id FROM public.users_profile u 
      WHERE p.hrco_email_raw IS NOT NULL 
        AND lower(u.email) = lower(trim(p.hrco_email_raw)) 
        AND u.is_active = true 
      LIMIT 1
    ) row_hrco ON true
  )
  SELECT
    e.row_num,
    e.raw_row,
    e.vcode,
    e.final_store_name,
    e.mother_acct,
    e.prov,
    e.city,
    e.position_val AS "position",
    e.emp_no,
    e.last_name,
    e.first_name,
    e.middle_name,
    e.date_hired,
    e.civil_status,
    e.rate_raw,
    e.birthdate_raw,
    e.contact_raw,
    e.address_raw,
    e.sched_days_raw,
    e.sched_time_raw,
    e.dayoff_raw,
    e.coord_raw,
    e.hrco_email_raw,
    e.row_final_hrco_id,
    e.row_needs_hrco,
    e.resolved_store_id,
    e.is_new_store,
    e.is_existing_emp,
    e.is_roving,
    e.roving_store_count,
    e.employment_type,
    e.required_hc_raw,
    e.with_penalty_raw,
    e.validation_errors,
    e.validation_flags,
    e.is_dup_pair,
    CASE
      WHEN jsonb_array_length(e.validation_errors) > 0 THEN 'blocked'
      WHEN e.is_dup_pair THEN 'skipped'
      WHEN jsonb_array_length(e.validation_flags) > 0 THEN 'flagged'
      ELSE 'valid'
    END AS validation_status
  FROM evaluated e;
END;
$func$;

REVOKE ALL ON FUNCTION public._evaluate_plantilla_import_rows(uuid, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._evaluate_plantilla_import_rows(uuid, uuid, jsonb) TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.approve_plantilla_import_batch(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '60s'
AS $function$
DECLARE
  v_uid            uuid := auth.uid();
  v_actor          uuid := public.get_current_profile_id();
  v_user_name      text;
  v_batch          public.plantilla_import_batches%ROWTYPE;
  v_acct_name      text;
  v_acct_hrco_id   uuid;
  v_acct_hrco_name text;

  -- Phase A locals
  v_srow               record;
  v_existing_store_id  uuid;
  v_new_store_id       uuid;
  v_old_store_snap     jsonb;
  v_pen_bool           boolean;
  v_stores_done        int := 0;

  -- Phase B locals
  v_vrow           record;
  v_emp_rec        record;
  v_store_rec      record;
  v_plantilla_id   uuid;
  v_primary_store_id uuid;
  v_parsed_rate    numeric;
  v_parsed_date_hired date;
  v_parsed_birthdate  date;
  v_store_cnt      int;
  v_filled         numeric(8,4);
  v_emp_name       text;
  v_old_plant_snap jsonb;
  v_old_slot_snap  jsonb;
  v_new_alloc_id   uuid;
  v_employees_done int := 0;
  v_alloc_done     int := 0;
  v_vacant_slots   int := 0;

  -- Target linkage locals
  v_store_acct_id     uuid;
  v_store_grp_id      uuid;
  v_target_account_id uuid;
  v_target_group_id   uuid;
  v_target_acct_name  text;

  -- HRCO resolution locals
  v_final_hrco_id   uuid;
  v_final_hrco_name text;
  v_needs_hrco      boolean;

  -- Slot claiming & assignment locals
  v_target_slot_id uuid;
  v_next_ordinal   int;
  v_batch_created_slot_ids uuid[] := '{}'::uuid[];

  -- Commit counts & pre-commit guards
  v_blocked_cnt int := 0;
  v_committable int := 0;
  v_approved_timestamp timestamptz;

  -- Error handling
  v_err_state text;
  v_err_msg   text;
  v_err_out   text;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  IF v_batch.status NOT IN ('pending_approval', 'commit_failed') THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval or commit_failed can be approved (current=%)', v_batch.status USING ERRCODE = '22023';
  END IF;

  SELECT full_name INTO v_user_name FROM public.users_profile WHERE id = v_actor;
  SELECT account_name, hrco_user_id INTO v_acct_name, v_acct_hrco_id
    FROM public.accounts WHERE id = v_batch.selected_account_id;

  IF v_acct_hrco_id IS NOT NULL THEN
    SELECT full_name INTO v_acct_hrco_name
      FROM public.users_profile
     WHERE id = v_acct_hrco_id;
  END IF;

  -- Pre-commit guard 1: Block approval strictly if there are hard-blocked rows
  SELECT count(*) INTO v_blocked_cnt
    FROM public.plantilla_import_rows
   WHERE batch_id = p_batch_id
     AND validation_status = 'blocked';

  IF v_blocked_cnt > 0 THEN
    RAISE EXCEPTION 'Cannot approve batch: % blocked rows must be resolved or removed first', v_blocked_cnt USING ERRCODE = '22023';
  END IF;

  -- Pre-commit guard 2: Committable includes valid and flagged rows with vcode
  SELECT count(*) INTO v_committable
    FROM public.plantilla_import_rows
   WHERE batch_id = p_batch_id
     AND validation_status IN ('valid', 'flagged')
     AND vcode IS NOT NULL;

  IF v_committable = 0 THEN
    RAISE EXCEPTION 'COMMIT_EMPTY: no committable rows in batch' USING ERRCODE = '22023';
  END IF;

  BEGIN
    -- ========================================================================
    -- Phase A: Store upsert for all committable rows (valid + flagged)
    -- ========================================================================
    FOR v_srow IN
      SELECT DISTINCT ON (vcode)
             vcode, store_name, mother_account, area_province, area_city,
             employment_type, with_penalty_raw, schedule_days, schedule_time,
             row_number, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid', 'flagged')
         AND vcode IS NOT NULL
       ORDER BY vcode, row_number
    LOOP
      v_pen_bool := (lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('yes','y','true','1'));

      SELECT to_jsonb(s.*) INTO v_old_store_snap
        FROM public.stores s
       WHERE upper(s.vcode) = upper(v_srow.vcode)
         AND (s.status = 'active' OR (s.account_id = v_batch.selected_account_id AND s.status = 'archived'))
       ORDER BY CASE WHEN s.status = 'active' THEN 1 ELSE 2 END, s.created_at LIMIT 1;

      IF v_old_store_snap IS NULL THEN
        INSERT INTO public.stores (
          vcode, store_name, mother_account, area_province, province, area_city,
          employment_type, with_penalty, schedule_days, schedule_time,
          group_id, account_id, status, hrco_user_id,
          created_by, updated_by, approved_by, approved_at, source_import_id
        ) VALUES (
          v_srow.vcode, v_srow.store_name, v_srow.mother_account,
          v_srow.area_province, v_srow.area_province, v_srow.area_city,
          COALESCE(v_srow.employment_type, 'stationary'), v_pen_bool, v_srow.schedule_days, v_srow.schedule_time,
          v_batch.selected_group_id, v_batch.selected_account_id, 'active', v_acct_hrco_id,
          v_uid, v_uid, v_uid, now(), p_batch_id
        ) RETURNING id INTO v_new_store_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_new_store_id, 'insert', NULL, v_uid);
      ELSE
        v_existing_store_id := (v_old_store_snap->>'id')::uuid;

        UPDATE public.stores
           SET store_name       = v_srow.store_name,
               mother_account   = COALESCE(v_srow.mother_account, mother_account),
               area_province    = COALESCE(v_srow.area_province, area_province),
               province         = COALESCE(v_srow.area_province, province),
               area_city        = COALESCE(v_srow.area_city, area_city),
               employment_type  = COALESCE(v_srow.employment_type, employment_type),
               with_penalty     = COALESCE(v_pen_bool, with_penalty),
               schedule_days    = COALESCE(v_srow.schedule_days, schedule_days),
               schedule_time    = COALESCE(v_srow.schedule_time, schedule_time),
               account_id       = COALESCE(stores.account_id, v_batch.selected_account_id),
               group_id         = COALESCE(stores.group_id, v_batch.selected_group_id),
               hrco_user_id     = COALESCE(v_acct_hrco_id, hrco_user_id),
               status           = 'active',
               is_active        = true,
               is_archived      = false,
               archived_at      = NULL,
               updated_at       = now(),
               updated_by       = v_uid,
               approved_by      = v_uid,
               approved_at      = now(),
               source_import_id = p_batch_id
         WHERE id = v_existing_store_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_existing_store_id, 'update', v_old_store_snap, v_uid);
      END IF;

      v_stores_done := v_stores_done + 1;
    END LOOP;

    -- ========================================================================
    -- Phase B1: Vacant Store Slot Creation (committable rows where employee_no IS NULL)
    -- ========================================================================
    FOR v_vrow IN
      SELECT vcode, store_name, position, area_province, area_city, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid', 'flagged')
         AND employee_no IS NULL
         AND vcode IS NOT NULL
       ORDER BY vcode, row_number
    LOOP
      v_new_store_id := NULL;
      v_store_acct_id := NULL;
      v_store_grp_id := NULL;

      SELECT id, account_id, group_id
        INTO v_new_store_id, v_store_acct_id, v_store_grp_id
        FROM public.stores
       WHERE upper(vcode) = upper(v_vrow.vcode) AND status = 'active'
       ORDER BY created_at LIMIT 1;

      v_target_account_id := COALESCE(v_batch.selected_account_id, v_store_acct_id);
      v_target_group_id   := COALESCE(v_batch.selected_group_id, v_store_grp_id);

      IF v_target_account_id IS NOT NULL AND (v_acct_name IS NULL OR v_acct_name = 'Unknown Account') THEN
        SELECT account_name INTO v_target_acct_name FROM public.accounts WHERE id = v_target_account_id;
      ELSE
        v_target_acct_name := v_acct_name;
      END IF;

      -- Calculate next available ordinal for this store
      SELECT COALESCE(MAX(slot_ordinal), 0) + 1 INTO v_next_ordinal
        FROM public.plantilla_slots
       WHERE store_id = v_new_store_id OR (store_id IS NULL AND upper(legacy_vcode) = upper(v_vrow.vcode));

      INSERT INTO public.plantilla_slots (
        store_id, account_id, group_id,
        position, employment_type, is_roving,
        slot_status, slot_ordinal, legacy_vcode,
        current_occupant_plantilla_id,
        created_at, updated_at, created_by, updated_by
      ) VALUES (
        v_new_store_id, v_target_account_id, v_target_group_id,
        COALESCE(v_vrow.position, 'Merchandiser'), 'stationary', false,
        'open', v_next_ordinal::smallint, v_vrow.vcode, NULL,
        now(), now(), v_actor, v_actor
      ) RETURNING id INTO v_target_slot_id;

      v_batch_created_slot_ids := array_append(v_batch_created_slot_ids, v_target_slot_id);

      -- Sync vacancies record for shadow view
      INSERT INTO public.vacancies (
        vcode, account, position, store_name, area_city, province, area_name,
        required_headcount, status, store_id, account_id, group_id,
        hrco_user_id, hrco_name,
        created_at, updated_at, created_by
      ) VALUES (
        v_vrow.vcode,
        COALESCE(v_target_acct_name, v_acct_name, 'Unknown Account'),
        COALESCE(v_vrow.position, 'Merchandiser'),
        v_vrow.store_name,
        v_vrow.area_city,
        v_vrow.area_province,
        v_vrow.area_province || ' - ' || v_vrow.area_city,
        1, 'Open', v_new_store_id, v_target_account_id, v_target_group_id,
        v_acct_hrco_id, v_acct_hrco_name,
        now(), now(), v_actor
      ) ON CONFLICT (vcode) DO UPDATE
      SET status = 'Open',
          account = CASE
            WHEN EXCLUDED.account IS NOT NULL AND EXCLUDED.account <> 'Unknown Account' THEN EXCLUDED.account
            ELSE COALESCE(NULLIF(vacancies.account, 'Unknown Account'), EXCLUDED.account)
          END,
          position = EXCLUDED.position,
          store_name = EXCLUDED.store_name,
          area_city = EXCLUDED.area_city,
          province = EXCLUDED.province,
          area_name = EXCLUDED.area_name,
          store_id = COALESCE(EXCLUDED.store_id, vacancies.store_id),
          account_id = COALESCE(EXCLUDED.account_id, vacancies.account_id),
          group_id = COALESCE(EXCLUDED.group_id, vacancies.group_id),
          required_headcount = GREATEST(vacancies.required_headcount, 1),
          hrco_user_id = COALESCE(EXCLUDED.hrco_user_id, vacancies.hrco_user_id),
          hrco_name = COALESCE(EXCLUDED.hrco_name, vacancies.hrco_name),
          deleted_at = NULL,
          is_archived = false,
          updated_at = now();

      INSERT INTO public.slot_history (
        slot_id, account_id, action_type, old_value, new_value,
        reason_code, performed_by, remarks, created_at
      ) VALUES (
        v_target_slot_id, v_target_account_id, 'created',
        NULL, 'open',
        CASE WHEN EXISTS (SELECT 1 FROM public.slot_reason_codes WHERE code = 'IMPORT_VACANT_SLOT') THEN 'IMPORT_VACANT_SLOT' ELSE NULL END,
        v_actor,
        format('Vacant slot created by baseline import batch %s', p_batch_id), now()
      );

      INSERT INTO public.plantilla_import_commit_snapshots
        (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
      VALUES (p_batch_id, v_vrow.row_id, 'slot', v_target_slot_id, 'insert', NULL, v_uid);

      v_vacant_slots := v_vacant_slots + 1;
    END LOOP;

    -- ========================================================================
    -- Phase B2: Assigned Employee Upsert & Slot Provisioning (valid + flagged)
    -- Enforces LAST-ROW-WINS persistence for coalesced demographic, compensation & rest-day fields
    -- ========================================================================
    FOR v_emp_rec IN
      SELECT
        employee_no,
        count(DISTINCT vcode)                                                       AS store_count,
        (array_agg(last_name   ORDER BY row_number DESC))[1]                        AS last_name,
        (array_agg(first_name  ORDER BY row_number DESC))[1]                        AS first_name,
        (array_agg(middle_name ORDER BY row_number DESC))[1]                        AS middle_name,
        (array_agg(position    ORDER BY row_number DESC) FILTER (WHERE position IS NOT NULL))[1] AS position,
        (array_agg(vcode       ORDER BY row_number) FILTER (WHERE vcode IS NOT NULL))[1] AS primary_vcode,
        (array_agg(store_name  ORDER BY row_number) FILTER (WHERE store_name IS NOT NULL))[1] AS primary_store_name,
        (array_agg(mother_account ORDER BY row_number) FILTER (WHERE mother_account IS NOT NULL))[1] AS mother_account,
        (array_agg(area_province ORDER BY row_number) FILTER (WHERE area_province IS NOT NULL))[1] AS area_province,
        (array_agg(area_city ORDER BY row_number) FILTER (WHERE area_city IS NOT NULL))[1] AS area_city,
        (array_agg(civil_status ORDER BY row_number DESC) FILTER (WHERE civil_status IS NOT NULL))[1] AS civil_status,
        (array_agg(rate_raw ORDER BY row_number DESC) FILTER (WHERE rate_raw IS NOT NULL))[1] AS rate_raw,
        (array_agg(birthdate_raw ORDER BY row_number DESC) FILTER (WHERE birthdate_raw IS NOT NULL))[1] AS birthdate_raw,
        (array_agg(date_hired_raw ORDER BY row_number DESC) FILTER (WHERE date_hired_raw IS NOT NULL))[1] AS date_hired_raw,
        (array_agg(contact_raw ORDER BY row_number DESC) FILTER (WHERE contact_raw IS NOT NULL))[1] AS contact_raw,
        (array_agg(address_raw ORDER BY row_number DESC) FILTER (WHERE address_raw IS NOT NULL))[1] AS address_raw,
        (array_agg(schedule_days ORDER BY row_number DESC) FILTER (WHERE schedule_days IS NOT NULL))[1] AS schedule_days,
        (array_agg(schedule_time ORDER BY row_number DESC) FILTER (WHERE schedule_time IS NOT NULL))[1] AS schedule_time,
        (array_agg(dayoff_raw ORDER BY row_number DESC) FILTER (WHERE dayoff_raw IS NOT NULL))[1] AS dayoff_raw,
        (array_agg(coordinator_raw ORDER BY row_number DESC) FILTER (WHERE coordinator_raw IS NOT NULL))[1] AS coordinator_raw,
        bool_or(needs_hrco) AS needs_hrco_agg,
        (array_agg(resolved_hrco_user_id ORDER BY row_number DESC) FILTER (WHERE resolved_hrco_user_id IS NOT NULL))[1] AS hrco_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid', 'flagged')
         AND employee_no IS NOT NULL
       GROUP BY employee_no
    LOOP
      v_employees_done := v_employees_done + 1;
      v_store_cnt := v_emp_rec.store_count;
      v_filled    := round(1.0 / GREATEST(v_store_cnt, 1), 4);
      v_emp_name  := v_emp_rec.last_name || ', ' || v_emp_rec.first_name
                     || COALESCE(' ' || v_emp_rec.middle_name, '');

      -- Resolve Primary Store ID
      v_primary_store_id := NULL;
      IF v_emp_rec.primary_vcode IS NOT NULL THEN
        SELECT id INTO v_primary_store_id
          FROM public.stores
         WHERE upper(vcode) = upper(v_emp_rec.primary_vcode) AND status = 'active'
         ORDER BY created_at LIMIT 1;
      END IF;

      -- Parse numeric rate and dates
      v_parsed_rate := public.safe_parse_numeric(v_emp_rec.rate_raw);
      v_parsed_date_hired := public.safe_parse_date(v_emp_rec.date_hired_raw);
      v_parsed_birthdate := public.safe_parse_date(v_emp_rec.birthdate_raw);

      -- HRCO resolution: row-level first, then Account assigned HRCO fallback
      v_final_hrco_id := COALESCE(v_emp_rec.hrco_id, v_acct_hrco_id);
      IF v_final_hrco_id IS NOT NULL THEN
        IF v_final_hrco_id = v_acct_hrco_id AND v_acct_hrco_name IS NOT NULL THEN
          v_final_hrco_name := v_acct_hrco_name;
        ELSE
          SELECT full_name INTO v_final_hrco_name
            FROM public.users_profile
           WHERE id = v_final_hrco_id;
        END IF;
        v_needs_hrco := false;
      ELSE
        v_final_hrco_name := NULL;
        v_needs_hrco := true;
      END IF;

      -- Plantilla lookup (active employees only; rolled-back inactive rows are NOT reused as update targets)
      v_plantilla_id := NULL;
      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no
         AND is_deleted = false
         AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation','Floating')
       LIMIT 1;

      SELECT to_jsonb(p.*) INTO v_old_plant_snap
        FROM public.plantilla p WHERE id = v_plantilla_id;

      IF v_plantilla_id IS NULL THEN
        -- Insert new plantilla record with all inherited fields
        INSERT INTO public.plantilla (
          employee_name, employee_no, emploc_no, account, status,
          account_id, last_name, first_name, middle_name,
          mother_account, position, deployment_type,
          store_id, store_name, vcode,
          area, area_name_snapshot,
          civil_status, rate, daily_rate, birthdate, date_of_birth, date_hired,
          contact_no, address,
          schedule, schedule_days, schedule_time, dayoff, coordinator,
          hrco_user_id_snapshot, hrco_name, needs_hrco,
          source_baseline_import_batch_id, created_by, moved_by_user_id
        ) VALUES (
          v_emp_name, v_emp_rec.employee_no, v_emp_rec.employee_no, v_acct_name, 'Active',
          v_batch.selected_account_id, v_emp_rec.last_name, v_emp_rec.first_name, v_emp_rec.middle_name,
          v_emp_rec.mother_account, v_emp_rec.position,
          CASE WHEN v_store_cnt > 1 THEN 'Roving' ELSE 'Stationary' END,
          v_primary_store_id, v_emp_rec.primary_store_name, v_emp_rec.primary_vcode,
          COALESCE(v_emp_rec.area_city, v_emp_rec.area_province),
          COALESCE(v_emp_rec.area_city, v_emp_rec.area_province),
          v_emp_rec.civil_status,
          v_parsed_rate,
          v_parsed_rate,
          v_parsed_birthdate,
          v_parsed_birthdate,
          v_parsed_date_hired,
          v_emp_rec.contact_raw, v_emp_rec.address_raw,
          v_emp_rec.schedule_days, v_emp_rec.schedule_days, v_emp_rec.schedule_time,
          v_emp_rec.dayoff_raw, v_emp_rec.coordinator_raw,
          v_final_hrco_id, v_final_hrco_name, v_needs_hrco,
          p_batch_id, v_actor, v_actor
        ) RETURNING id INTO v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'insert', NULL, v_uid);
      ELSE
        -- Update existing plantilla record with inherited fields (last-row-wins)
        UPDATE public.plantilla
           SET employee_name      = v_emp_name,
               last_name          = v_emp_rec.last_name,
               first_name         = v_emp_rec.first_name,
               middle_name        = v_emp_rec.middle_name,
               mother_account     = COALESCE(v_emp_rec.mother_account, mother_account),
               position           = COALESCE(v_emp_rec.position, position),
               deployment_type    = CASE WHEN v_store_cnt > 1 THEN 'Roving' ELSE 'Stationary' END,
               store_id           = COALESCE(v_primary_store_id, store_id),
               store_name         = COALESCE(v_emp_rec.primary_store_name, store_name),
               vcode              = COALESCE(v_emp_rec.primary_vcode, vcode),
               rate               = COALESCE(v_parsed_rate, rate),
               daily_rate         = COALESCE(v_parsed_rate, daily_rate),
               date_hired         = COALESCE(v_parsed_date_hired, date_hired),
               address            = COALESCE(v_emp_rec.address_raw, address),
               contact_no         = COALESCE(v_emp_rec.contact_raw, contact_no),
               birthdate          = COALESCE(v_parsed_birthdate, birthdate),
               date_of_birth      = COALESCE(v_parsed_birthdate, date_of_birth),
               civil_status       = COALESCE(v_emp_rec.civil_status, civil_status),
               schedule_days      = COALESCE(v_emp_rec.schedule_days, schedule_days),
               schedule_time      = COALESCE(v_emp_rec.schedule_time, schedule_time),
               dayoff             = COALESCE(v_emp_rec.dayoff_raw, dayoff),
               coordinator        = COALESCE(v_emp_rec.coordinator_raw, coordinator),
               hrco_user_id_snapshot = COALESCE(v_final_hrco_id, hrco_user_id_snapshot),
               hrco_name          = COALESCE(v_final_hrco_name, hrco_name),
               needs_hrco         = CASE WHEN v_final_hrco_id IS NOT NULL THEN false ELSE COALESCE(v_emp_rec.needs_hrco_agg, needs_hrco) END,
               updated_at         = now(),
               source_baseline_import_batch_id = p_batch_id
         WHERE id = v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'update', v_old_plant_snap, v_uid);
      END IF;

      -- Snapshot existing active allocations prior to deactivation for rollback restoration
      INSERT INTO public.plantilla_import_commit_snapshots
        (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
      SELECT
        p_batch_id, 'allocation', a.id, 'update', to_jsonb(a.*), v_uid
        FROM public.employee_store_allocations a
       WHERE a.employee_no = v_emp_rec.employee_no
         AND a.is_active
         AND a.account_id = v_batch.selected_account_id;

      -- Deactivate old allocations
      UPDATE public.employee_store_allocations
         SET is_active = false, effective_end = CURRENT_DATE
        WHERE employee_no = v_emp_rec.employee_no
          AND is_active
          AND account_id = v_batch.selected_account_id;

      -- Store allocations loop (committable valid + flagged)
      FOR v_store_rec IN
        SELECT DISTINCT ON (pir.vcode)
               pir.vcode, pir.store_name, pir.schedule_days, pir.schedule_time
          FROM public.plantilla_import_rows pir
         WHERE pir.batch_id = p_batch_id
           AND pir.employee_no = v_emp_rec.employee_no
           AND pir.validation_status IN ('valid', 'flagged')
         ORDER BY pir.vcode, pir.row_number
      LOOP
        v_new_store_id := NULL;
        v_store_acct_id := NULL;
        v_store_grp_id := NULL;

        SELECT id, account_id, group_id
          INTO v_new_store_id, v_store_acct_id, v_store_grp_id
          FROM public.stores
         WHERE upper(vcode) = upper(v_store_rec.vcode) AND status = 'active'
         ORDER BY created_at LIMIT 1;

        v_target_account_id := COALESCE(v_batch.selected_account_id, v_store_acct_id);
        v_target_group_id   := COALESCE(v_batch.selected_group_id, v_store_grp_id);

        INSERT INTO public.employee_store_allocations (
          plantilla_id, employee_no,
          store_id, vcode, store_name,
          account_id, group_id,
          filled_hc, active_store_count,
          schedule_days, schedule_time,
          effective_start, is_active,
          source_import_batch_id, created_by
        ) VALUES (
          v_plantilla_id, v_emp_rec.employee_no,
          v_new_store_id, v_store_rec.vcode, v_store_rec.store_name,
          v_target_account_id, v_target_group_id,
          v_filled, v_store_cnt,
          v_store_rec.schedule_days, v_store_rec.schedule_time,
          CURRENT_DATE, true,
          p_batch_id, v_actor
        ) RETURNING id INTO v_new_alloc_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'allocation', v_new_alloc_id, 'insert', NULL, v_uid);

        v_alloc_done := v_alloc_done + 1;

        -- Sync active roving link in plantilla_store_links for safe view consistency
        INSERT INTO public.plantilla_store_links (
          plantilla_id, vcode, store_name, account, status, linked_at
        ) VALUES (
          v_plantilla_id, v_store_rec.vcode, v_store_rec.store_name, v_acct_name, 'Active', now()
        ) ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL)
        DO UPDATE SET
          store_name = EXCLUDED.store_name,
          account = EXCLUDED.account,
          status = 'Active';

        -- Store-level idempotent slot reuse, pre-existing vacant claiming, or slot provisioning
        v_target_slot_id := NULL;

        -- Step 1: Check if employee already occupies an active slot in this store
        SELECT id INTO v_target_slot_id
          FROM public.plantilla_slots
         WHERE (store_id = v_new_store_id OR (store_id IS NULL AND upper(legacy_vcode) = upper(v_store_rec.vcode)))
           AND current_occupant_plantilla_id = v_plantilla_id
           AND slot_status IN ('occupied', 'filled')
         LIMIT 1;

        IF v_target_slot_id IS NOT NULL THEN
          -- Re-import / idempotent update of existing active slot for this employee in this store
          UPDATE public.plantilla_slots
             SET store_id        = COALESCE(store_id, v_new_store_id),
                 account_id      = COALESCE(account_id, v_target_account_id),
                 group_id        = COALESCE(group_id, v_target_group_id),
                 position        = COALESCE(v_emp_rec.position, position),
                 is_roving       = (v_store_cnt > 1),
                 employment_type = CASE WHEN v_store_cnt > 1 THEN 'roving' ELSE 'stationary' END,
                 updated_at      = now(),
                 updated_by      = v_actor
           WHERE id = v_target_slot_id;

        ELSE
          -- Step 2: Employee does NOT already have an active slot here.
          -- Can we claim an open vacant slot that existed prior to this import (NOT created in Phase B1 of this batch)?
          SELECT id INTO v_target_slot_id
            FROM public.plantilla_slots
           WHERE (store_id = v_new_store_id OR (store_id IS NULL AND upper(legacy_vcode) = upper(v_store_rec.vcode)))
             AND slot_status = 'open'
             AND (v_batch_created_slot_ids IS NULL OR id <> ALL(v_batch_created_slot_ids))
           ORDER BY slot_ordinal ASC
           LIMIT 1;

          IF v_target_slot_id IS NOT NULL THEN
            -- Capture snapshot before claiming pre-existing slot
            SELECT to_jsonb(ps.*) INTO v_old_slot_snap
              FROM public.plantilla_slots ps
             WHERE id = v_target_slot_id;

            -- Claim pre-existing vacant slot
            UPDATE public.plantilla_slots
               SET slot_status = 'occupied',
                   store_id = COALESCE(store_id, v_new_store_id),
                   account_id = COALESCE(account_id, v_target_account_id),
                   group_id = COALESCE(group_id, v_target_group_id),
                   position = COALESCE(v_emp_rec.position, position),
                   is_roving = (v_store_cnt > 1),
                   employment_type = CASE WHEN v_store_cnt > 1 THEN 'roving' ELSE 'stationary' END,
                   current_occupant_plantilla_id = v_plantilla_id,
                   updated_at = now(),
                   updated_by = v_actor
             WHERE id = v_target_slot_id;

            -- Close / mark linked vacancies as Filled
            UPDATE public.vacancies
               SET status = 'Filled',
                   updated_at = now()
             WHERE upper(vcode) = upper(v_store_rec.vcode)
               AND status = 'Open';

            INSERT INTO public.slot_history (
              slot_id, account_id, action_type, old_value, new_value,
              reason_code, performed_by, remarks, created_at
            ) VALUES (
              v_target_slot_id, v_target_account_id, 'occupied',
              'open', 'occupied',
              CASE WHEN EXISTS (SELECT 1 FROM public.slot_reason_codes WHERE code = 'IMPORT_CLAIM_VACANT') THEN 'IMPORT_CLAIM_VACANT' ELSE NULL END,
              v_actor,
              format('Claimed vacant slot for employee %s via batch %s', v_emp_rec.employee_no, p_batch_id),
              now()
            );

            INSERT INTO public.plantilla_import_commit_snapshots
              (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
            VALUES (p_batch_id, 'slot', v_target_slot_id, 'update', v_old_slot_snap, v_uid);

          ELSE
            -- Step 3: No pre-existing open slot exists. Create a new occupied slot with incremented ordinal
            SELECT COALESCE(MAX(slot_ordinal), 0) + 1 INTO v_next_ordinal
              FROM public.plantilla_slots
             WHERE store_id = v_new_store_id OR (store_id IS NULL AND upper(legacy_vcode) = upper(v_store_rec.vcode));

            INSERT INTO public.plantilla_slots (
              store_id, account_id, group_id,
              position, employment_type, is_roving,
              slot_status, slot_ordinal, legacy_vcode,
              current_occupant_plantilla_id,
              created_at, updated_at, created_by, updated_by
            ) VALUES (
              v_new_store_id, v_target_account_id, v_target_group_id,
              COALESCE(v_emp_rec.position, 'Unknown'),
              CASE WHEN v_store_cnt > 1 THEN 'roving' ELSE 'stationary' END,
              (v_store_cnt > 1),
              'occupied', v_next_ordinal::smallint, v_store_rec.vcode,
              v_plantilla_id,
              now(), now(), v_actor, v_actor
            ) RETURNING id INTO v_target_slot_id;

            INSERT INTO public.slot_history (
              slot_id, account_id, action_type, old_value, new_value,
              reason_code, performed_by, remarks, created_at
            ) VALUES (
              v_target_slot_id, v_target_account_id, 'occupied',
              NULL, 'occupied',
              CASE WHEN EXISTS (SELECT 1 FROM public.slot_reason_codes WHERE code = 'IMPORT_OCCUPIED') THEN 'IMPORT_OCCUPIED' ELSE NULL END,
              v_actor,
              format('New occupied slot ordinal %s for employee %s', v_next_ordinal, v_emp_rec.employee_no),
              now()
            );

            INSERT INTO public.plantilla_import_commit_snapshots
              (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
            VALUES (p_batch_id, 'slot', v_target_slot_id, 'insert', NULL, v_uid);
          END IF;
        END IF;

      END LOOP;

    END LOOP;

    -- Update batch status with ADR-002 rollback governance metadata
    v_approved_timestamp := clock_timestamp();
    UPDATE public.plantilla_import_batches
       SET status              = 'approved',
           approved_by         = v_uid,
           approved_at         = v_approved_timestamp,
           approved_by_name    = v_user_name,
           rejection_reason    = NULL,
           commit_error        = NULL,
           committed_stores    = v_stores_done,
           committed_employees = v_employees_done,
           stores_created      = v_stores_done,
           employees_created   = v_employees_done,
           allocations_created = v_alloc_done,
           rollback_ready      = true,
           updated_at          = v_approved_timestamp
     WHERE id = p_batch_id;

    RETURN jsonb_build_object(
      'success', true,
      'batch_id', p_batch_id,
      'status', 'approved',
      'stores_processed', v_stores_done,
      'employees_processed', v_employees_done,
      'allocations_created', v_alloc_done,
      'vacant_slots_created', v_vacant_slots,
      'rollback_ready', true,
      'approved_at', v_approved_timestamp
    );

  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_err_state = RETURNED_SQLSTATE,
      v_err_msg   = MESSAGE_TEXT;
    v_err_out := format('[%s] %s', v_err_state, v_err_msg);

    UPDATE public.plantilla_import_batches
       SET status       = 'commit_failed',
           commit_error = v_err_out
     WHERE id = p_batch_id;

    RAISE EXCEPTION 'COMMIT_FAILED: %', v_err_out USING ERRCODE = v_err_state;
  END;
END;
$function$;

REVOKE ALL ON FUNCTION public.approve_plantilla_import_batch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_batch(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.approve_plantilla_import_batch(uuid) IS
  'OHM2026_1053: Canonical merge of Migration 086 (stores, plantilla_slots, plantilla_store_links, vacancies, slot_history, rollback snapshots) + ADR-002 Rule #17 Last-Row-Wins employee field coalescing.';

