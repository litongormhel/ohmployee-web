-- ============================================================================
-- Migration: 20262606000094_adr002_bidirectional_identity_lock.sql
-- ADR-002 Invariant #16 Bi-Directional Identity Lock: 1 Person = 1 EMPLOYEE_NO
-- Deploys updated public._evaluate_plantilla_import_rows with name_emp_conflicts
-- and cross-table reverse checks (db_name_conflict, db_emp_name_conflict) to
-- guarantee remote Staging and Production databases enforce the bi-directional lock.
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

          -- Inactive Plantilla Status Lock (Rule #1 Invariant)
          SELECT CASE WHEN p.emp_no IS NOT NULL AND db_plantilla.id IS NOT NULL AND db_plantilla.status IN ('Inactive','Rejected Deactivation') THEN jsonb_build_object('field','EMPLOYEE_NO','conflict_type','inactive_or_archived_existing_record','msg',format('Employee %s exists in plantilla with inactive/archived status ("%s"). Re-import blocked.', p.emp_no, db_plantilla.status)) END UNION ALL

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
        pl.date_hired::text AS date_hired
      FROM public.plantilla pl 
      WHERE pl.employee_no = p.emp_no 
        AND pl.is_deleted = false 
      ORDER BY 
        CASE 
          WHEN pl.status IN ('Active','For Deactivation','On Leave','Pending Deactivation') THEN 1 
          WHEN pl.status IN ('Inactive','Rejected Deactivation') THEN 2 
          ELSE 3 
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
