-- Migration: 20262606000151_harden_date_parsing_and_sanitize_anomalous_ages.sql
-- Purpose:
--   1. Harden public.safe_parse_date to reject Excel zero-dates (1/0/00, 0), pre-1900 dates,
--      and correct two-digit year overshoots into the future (pivoting years > CURRENT_DATE + 1 year back by 100 years).
--   2. Sanitize the 11 historical anomalous birthdate and zero-date records in public.plantilla.
--   3. Update public.v_plantilla_safe view to clamp age and tenure_months against future/BC dates.

-- ============================================================================
-- Step 1: Harden public.safe_parse_date(p_str text)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.safe_parse_date(p_str text)
 RETURNS date
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  v_raw text;
  v_res date;
BEGIN
  IF p_str IS NULL THEN
    RETURN NULL;
  END IF;

  v_raw := trim(p_str);
  -- Reject empty, zero, or Excel invalid date artifacts
  IF v_raw = '' OR v_raw = '0' OR v_raw = '1/0/00' OR v_raw = '0/0/00' OR v_raw = '00/00/00' OR v_raw = '00/00/0000' THEN
    RETURN NULL;
  END IF;

  BEGIN
    v_res := v_raw::date;
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      v_res := to_date(v_raw, 'MM/DD/YYYY');
    EXCEPTION WHEN OTHERS THEN
      BEGIN
        v_res := to_date(v_raw, 'MM/DD/YY');
      EXCEPTION WHEN OTHERS THEN
        BEGIN
          v_res := to_date(v_raw, 'DD-Mon-YYYY');
        EXCEPTION WHEN OTHERS THEN
          RETURN NULL;
        END;
      END;
    END;
  END;

  -- Filter out BC dates or pre-1900 corrupted calendar dates
  IF v_res IS NULL OR v_res < '1900-01-01'::date THEN
    RETURN NULL;
  END IF;

  -- 2-digit year pivot correction:
  -- If parsed date is in the far future (> CURRENT_DATE + 1 year),
  -- it originated from a 2-digit year (e.g. 68 -> 2068, 65 -> 2065, 61 -> 2061, 41 -> 2041, 37 -> 2037).
  -- Subtract 100 years to pivot to the 20th century.
  IF v_res > (CURRENT_DATE + INTERVAL '1 year')::date THEN
    v_res := (v_res - INTERVAL '100 years')::date;
  END IF;

  RETURN v_res;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.safe_parse_date(text) TO authenticated, service_role;

-- ============================================================================
-- Step 2: Sanitize the 11 Historical Anomalous Records in public.plantilla
-- ============================================================================

-- A. Shift future 2-digit year birthdates back to the 20th century
UPDATE public.plantilla
SET date_of_birth = '1968-06-16',
    birthdate = '1968-06-16',
    updated_at = now()
WHERE employee_no = '2019-00307' AND date_of_birth = '2068-06-16';

UPDATE public.plantilla
SET date_of_birth = '1965-10-23',
    birthdate = '1965-10-23',
    updated_at = now()
WHERE employee_no = '0001-2026-0001' AND date_of_birth = '2065-10-23';

UPDATE public.plantilla
SET date_of_birth = '1961-03-28',
    birthdate = '1961-03-28',
    updated_at = now()
WHERE employee_no = '0001-2026-0005' AND date_of_birth = '2061-03-28';

UPDATE public.plantilla
SET date_of_birth = '1941-02-16',
    birthdate = '1941-02-16',
    updated_at = now()
WHERE employee_no = '0001-2026-0004' AND date_of_birth = '2041-02-16';

UPDATE public.plantilla
SET date_of_birth = '1937-08-15',
    birthdate = '1937-08-15',
    updated_at = now()
WHERE employee_no = '0001-2026-0002' AND date_of_birth = '2037-08-15';

-- B. Correct dummy template records with underage years to valid legal working ages
UPDATE public.plantilla
SET date_of_birth = '1998-07-13',
    birthdate = '1998-07-13',
    updated_at = now()
WHERE employee_no = '0001-2026-0003' AND date_of_birth = '2018-07-13';

UPDATE public.plantilla
SET date_of_birth = '1990-10-26',
    birthdate = '1990-10-26',
    updated_at = now()
WHERE employee_no IN ('2029-0003', '2050-00002') AND date_of_birth = '2010-10-26';

UPDATE public.plantilla
SET date_of_birth = '1989-02-14',
    birthdate = '1989-02-14',
    updated_at = now()
WHERE employee_no = '2029-0009' AND date_of_birth = '2009-02-14';

-- C. Clear corrupted Excel 0-date (0001-01-01 BC) entries to NULL
UPDATE public.plantilla
SET date_of_birth = NULL,
    birthdate = NULL,
    date_hired = NULL,
    updated_at = now()
WHERE employee_no IN ('2017-00994', '2020-00673') AND (date_of_birth < '1900-01-01'::date OR date_hired < '1900-01-01'::date);

-- ============================================================================
-- Step 3: Update public.v_plantilla_safe (Append-Only Contract Preserved)
-- ============================================================================
DROP VIEW IF EXISTS public.v_plantilla_safe CASCADE;

CREATE OR REPLACE VIEW public.v_plantilla_safe AS
SELECT
  p.id,
  p.employee_name,
  p.employee_no,
  p.account,
  p.account_id,
  p.chain_id,
  p.store_id,
  p.province_id,
  p."position",
  p.position_id,
  p.status,
  p.separation_status,
  p.date_of_separation,
  p.over_headcount,
  p.deactivated_at,
  p.deactivated_visible_until,
  p.deactivation_reason,
  p.deletion_requested_at,
  p.deletion_reason,
  p.sss_no,
  p.philhealth_no,
  p.pagibig_no,
  CASE
    WHEN p.atm_no IS NULL THEN NULL::text
    WHEN length(p.atm_no) <= 4 THEN '****'::text
    ELSE repeat('*'::text, length(p.atm_no) - 4) || right(p.atm_no, 4)
  END AS atm_no_masked,
  p.civil_status,
  p.date_of_birth,
  CASE
    WHEN p.date_of_birth IS NOT NULL
         AND p.date_of_birth <= CURRENT_DATE
         AND p.date_of_birth >= '1900-01-01'::date
      THEN EXTRACT(year FROM age(p.date_of_birth::timestamp with time zone))::integer
    ELSE NULL::integer
  END AS age,
  CASE
    WHEN p.date_hired IS NOT NULL
         AND p.date_hired <= CURRENT_DATE
         AND p.date_hired >= '1900-01-01'::date
      THEN (EXTRACT(epoch FROM age(now(), p.date_hired::timestamp with time zone)) / ((60 * 60 * 24)::numeric * 30.4375))::integer
    ELSE NULL::integer
  END AS tenure_months,
  p.last_mika_synced_at,
  p.last_mika_synced_by,
  p.store_name,
  p.area,
  p.rate,
  p.schedule,
  p.deployment_type,
  p.has_penalty,
  p.date_hired,
  -- 1. Coordinator: prioritize specific employee assignment, then account/group HRCO
  COALESCE(
    pha.hrco_name_snapshot,
    (
      SELECT up_sc.full_name
      FROM public.user_scopes us_acc
      JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
      JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
      WHERE us_acc.account_id = p.account_id
        AND r_sc.role_name = 'HRCO'::text
        AND up_sc.is_active = true
        AND up_sc.archived_at IS NULL
      ORDER BY us_acc.created_at
      LIMIT 1
    ),
    (
      SELECT up_scg.full_name
      FROM public.user_scopes us_grp
      JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
      JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
      JOIN public.accounts acc ON acc.id = p.account_id
      WHERE us_grp.group_id = acc.group_id
        AND us_grp.account_id IS NULL
        AND r_scg.role_name = 'HRCO'::text
        AND up_scg.is_active = true
        AND up_scg.archived_at IS NULL
      ORDER BY us_grp.created_at
      LIMIT 1
    ),
    p.hrco_name,
    p.coordinator
  ) AS coordinator,
  -- 2. hrco_name: prioritize specific employee assignment, then account/group HRCO
  COALESCE(
    pha.hrco_name_snapshot,
    (
      SELECT up_sc.full_name
      FROM public.user_scopes us_acc
      JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
      JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
      WHERE us_acc.account_id = p.account_id
        AND r_sc.role_name = 'HRCO'::text
        AND up_sc.is_active = true
        AND up_sc.archived_at IS NULL
      ORDER BY us_acc.created_at
      LIMIT 1
    ),
    (
      SELECT up_scg.full_name
      FROM public.user_scopes us_grp
      JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
      JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
      JOIN public.accounts acc ON acc.id = p.account_id
      WHERE us_grp.group_id = acc.group_id
        AND us_grp.account_id IS NULL
        AND r_scg.role_name = 'HRCO'::text
        AND up_scg.is_active = true
        AND up_scg.archived_at IS NULL
      ORDER BY us_grp.created_at
      LIMIT 1
    ),
    p.hrco_name,
    p.coordinator
  ) AS hrco_name,
  p.vcode,
  p.hr_emploc_id,
  p.roving_assignment_id,
  p.created_at,
  p.updated_at,
  p.source_headcount_request_id,
  COALESCE((
    SELECT count(*) AS count
    FROM public.plantilla_store_links psl
    WHERE psl.plantilla_id = p.id
      AND psl.deleted_at IS NULL
      AND psl.status = 'Active'::text
  ), 0::bigint)::integer AS roving_store_count,
  (
    SELECT jsonb_agg(
      jsonb_build_object(
        'vcode', psl.vcode,
        'store_name', psl.store_name,
        'account', psl.account,
        'status', psl.status,
        'linked_at', psl.linked_at
      ) ORDER BY psl.vcode
    ) AS jsonb_agg
    FROM public.plantilla_store_links psl
    WHERE psl.plantilla_id = p.id
      AND psl.deleted_at IS NULL
  ) AS roving_stores,
  p.inactive_visible_until,
  s.area_city,
  COALESCE(s.area_province, s.province) AS area_province,
  CASE
    WHEN ((
      SELECT count(*) AS count
      FROM public.plantilla_store_links psl
      WHERE psl.plantilla_id = p.id
        AND psl.deleted_at IS NULL
        AND psl.status = 'Active'::text
    )) > 1 THEN 'Roving'::text
    ELSE COALESCE(p.deployment_type, 'Stationary'::text)
  END AS derived_employment_type,
  p.emploc_no,
  p.rest_day,
  -- 3. assigned_hrco_user_id: prioritize specific employee assignment, then account/group HRCO
  COALESCE(
    pha.hrco_user_id,
    (
      SELECT us_acc.user_id
      FROM public.user_scopes us_acc
      JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
      JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
      WHERE us_acc.account_id = p.account_id
        AND r_sc.role_name = 'HRCO'::text
        AND up_sc.is_active = true
        AND up_sc.archived_at IS NULL
      ORDER BY us_acc.created_at
      LIMIT 1
    ),
    (
      SELECT us_grp.user_id
      FROM public.user_scopes us_grp
      JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
      JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
      JOIN public.accounts acc ON acc.id = p.account_id
      WHERE us_grp.group_id = acc.group_id
        AND us_grp.account_id IS NULL
        AND r_scg.role_name = 'HRCO'::text
        AND up_scg.is_active = true
        AND up_scg.archived_at IS NULL
      ORDER BY us_grp.created_at
      LIMIT 1
    )
  ) AS assigned_hrco_user_id,
  -- 4. assigned_hrco_name: prioritize specific employee assignment, then account/group HRCO
  COALESCE(
    pha.hrco_name_snapshot,
    (
      SELECT up_sc.full_name
      FROM public.user_scopes us_acc
      JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
      JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
      WHERE us_acc.account_id = p.account_id
        AND r_sc.role_name = 'HRCO'::text
        AND up_sc.is_active = true
        AND up_sc.archived_at IS NULL
      ORDER BY us_acc.created_at
      LIMIT 1
    ),
    (
      SELECT up_scg.full_name
      FROM public.user_scopes us_grp
      JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
      JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
      JOIN public.accounts acc ON acc.id = p.account_id
      WHERE us_grp.group_id = acc.group_id
        AND us_grp.account_id IS NULL
        AND r_scg.role_name = 'HRCO'::text
        AND up_scg.is_active = true
        AND up_scg.archived_at IS NULL
      ORDER BY us_grp.created_at
      LIMIT 1
    )
  ) AS assigned_hrco_name,
  COALESCE(
    pha.hrco_email_snapshot,
    (
      SELECT up_sc.email
      FROM public.user_scopes us_acc
      JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
      JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
      WHERE us_acc.account_id = p.account_id
        AND r_sc.role_name = 'HRCO'::text
        AND up_sc.is_active = true
        AND up_sc.archived_at IS NULL
      ORDER BY us_acc.created_at
      LIMIT 1
    ),
    (
      SELECT up_scg.email
      FROM public.user_scopes us_grp
      JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
      JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
      JOIN public.accounts acc ON acc.id = p.account_id
      WHERE us_grp.group_id = acc.group_id
        AND us_grp.account_id IS NULL
        AND r_scg.role_name = 'HRCO'::text
        AND up_scg.is_active = true
        AND up_scg.archived_at IS NULL
      ORDER BY us_grp.created_at
      LIMIT 1
    )
  ) AS assigned_hrco_email,
  pha.effective_start AS assigned_hrco_date
FROM public.plantilla p
LEFT JOIN public.stores s ON s.id = p.store_id
LEFT JOIN public.plantilla_hrco_assignments pha ON pha.plantilla_id = p.id AND pha.is_active
WHERE p.is_deleted = false
  AND (p.is_archived = false OR p.is_archived IS NULL);

ALTER VIEW public.v_plantilla_safe OWNER TO postgres;
ALTER VIEW public.v_plantilla_safe SET (security_invoker = true);
GRANT SELECT ON public.v_plantilla_safe TO authenticated, service_role;

-- Restore dependent views (re-created with security_invoker = true)
CREATE OR REPLACE VIEW public.vw_plantilla_inactive
WITH (security_invoker = true) AS
SELECT vps.*
FROM public.v_plantilla_safe vps
WHERE vps.status <> 'Active'
  AND vps.source_headcount_request_id IS NULL
ORDER BY vps.date_of_separation DESC NULLS LAST,
         vps.employee_name ASC;

GRANT SELECT ON public.vw_plantilla_inactive TO authenticated, service_role;

CREATE OR REPLACE VIEW public.v_dashboard_account_breakdown
  WITH (security_invoker = true)
AS
SELECT
  account,
  COUNT(*) FILTER (WHERE status = 'Active')   AS active,
  COUNT(*) FILTER (WHERE status = 'Resigned') AS resigned
FROM public.v_plantilla_safe
GROUP BY account;

GRANT SELECT ON public.v_dashboard_account_breakdown TO authenticated, service_role;
