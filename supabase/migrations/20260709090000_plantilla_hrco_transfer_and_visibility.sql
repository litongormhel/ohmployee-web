-- Migration: 20260709090000_plantilla_hrco_transfer_and_visibility
-- Created: 2026-07-09
-- Purpose: Implement HRCO ownership transfer (single + bulk) and assigned-HRCO visibility.

BEGIN;

-- 1. Add foreign key from plantilla_hrco_assignments(assigned_by) to users_profile(id) for nested query resolution
ALTER TABLE public.plantilla_hrco_assignments
  DROP CONSTRAINT IF EXISTS fk_hrco_assignments_assigned_by,
  ADD CONSTRAINT fk_hrco_assignments_assigned_by FOREIGN KEY (assigned_by) REFERENCES public.users_profile(id);

-- 2. Bulk/Single HRCO transfer function
CREATE OR REPLACE FUNCTION public.fn_transfer_employee_hrco(
  p_plantilla_ids uuid[],
  p_hrco_user_id uuid,
  p_reason text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_plantilla_id uuid;
  v_account_id   uuid;
  v_employee_no  text;
  v_count        integer := 0;
  v_profile_id   uuid;
BEGIN
  -- Check permission: Encoder, Head Admin, Super Admin only
  IF NOT public.fn_can_assign_hrco() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required' USING ERRCODE = '42501';
  END IF;

  v_profile_id := public.get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'profile_not_found' USING ERRCODE = 'P0002';
  END IF;

  FOREACH v_plantilla_id IN ARRAY p_plantilla_ids
  LOOP
    -- Lock row for update
    SELECT account_id, employee_no INTO v_account_id, v_employee_no
      FROM public.plantilla
     WHERE id = v_plantilla_id AND NOT is_deleted
     FOR UPDATE;

    IF v_account_id IS NULL THEN
      RAISE EXCEPTION 'plantilla_not_found for id: %', v_plantilla_id USING ERRCODE = 'P0002';
    END IF;

    -- Validate target HRCO belongs to the same account as the employee
    IF NOT public.fn_is_valid_hrco_for_account(p_hrco_user_id, v_account_id) THEN
      RAISE EXCEPTION 'invalid_hrco: not an HRCO on this account roster for employee %', v_employee_no USING ERRCODE = '22023';
    END IF;

    -- Deactivate any existing active assignment (archive-only, no hard delete)
    UPDATE public.plantilla_hrco_assignments
       SET is_active = false, effective_end = now()
     WHERE plantilla_id = v_plantilla_id AND is_active;

    -- Insert new assignment record
    INSERT INTO public.plantilla_hrco_assignments (
      plantilla_id, employee_no, account_id, hrco_user_id,
      hrco_email_snapshot, hrco_name_snapshot,
      assigned_by, assignment_source
    )
    SELECT v_plantilla_id, v_employee_no, v_account_id, p_hrco_user_id,
           up.email, up.full_name,
           v_profile_id, 'manual'
      FROM public.users_profile up
     WHERE up.auth_user_id = p_hrco_user_id;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- Grant execution to authenticated role
REVOKE ALL ON FUNCTION public.fn_transfer_employee_hrco(uuid[], uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_transfer_employee_hrco(uuid[], uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_transfer_employee_hrco(uuid[], uuid, text) TO authenticated;

-- 3. Drop and recreate public.v_plantilla_safe view to expose assigned HRCO info
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
    ELSE repeat('*', length(p.atm_no) - 4) || right(p.atm_no, 4)
  END AS atm_no_masked,
  p.civil_status,
  p.date_of_birth,
  CASE
    WHEN p.date_of_birth IS NOT NULL
      THEN EXTRACT(year FROM age(p.date_of_birth::timestamptz))::integer
    ELSE NULL::integer
  END AS age,
  CASE
    WHEN p.date_hired IS NOT NULL
      THEN (EXTRACT(epoch FROM age(now(), p.date_hired::timestamptz))
           / (60 * 60 * 24 * 30.4375))::integer
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
  p.coordinator,
  p.hrco_name,
  p.vcode,
  p.hr_emploc_id,
  p.roving_assignment_id,
  p.created_at,
  p.updated_at,
  p.source_headcount_request_id,
  -- Computed: roving store count and store-link snapshot
  COALESCE((
    SELECT COUNT(*)
      FROM public.plantilla_store_links psl
     WHERE psl.plantilla_id = p.id
       AND psl.deleted_at IS NULL
       AND psl.status = 'Active'
  ), 0)::integer AS roving_store_count,
  (
    SELECT jsonb_agg(
      jsonb_build_object(
        'vcode',     psl.vcode,
        'store_name',psl.store_name,
        'account',   psl.account,
        'status',    psl.status,
        'linked_at', psl.linked_at
      ) ORDER BY psl.vcode
    )
      FROM public.plantilla_store_links psl
     WHERE psl.plantilla_id = p.id
       AND psl.deleted_at IS NULL
  ) AS roving_stores,
  p.inactive_visible_until,
  s.area_city                           AS area_city,
  COALESCE(s.area_province, s.province) AS area_province,
  CASE
    WHEN (
      SELECT COUNT(*)
        FROM public.plantilla_store_links psl
       WHERE psl.plantilla_id = p.id
         AND psl.deleted_at IS NULL
         AND psl.status = 'Active'
    ) > 1
    THEN 'Roving'
    ELSE COALESCE(p.deployment_type, 'Stationary')
  END AS derived_employment_type,
  p.emploc_no,
  p.rest_day,
  -- Added assigned HRCO columns
  pha.hrco_user_id AS assigned_hrco_user_id,
  pha.hrco_name_snapshot AS assigned_hrco_name,
  pha.hrco_email_snapshot AS assigned_hrco_email,
  pha.effective_start AS assigned_hrco_date
FROM public.plantilla p
LEFT JOIN public.stores s ON s.id = p.store_id
LEFT JOIN public.plantilla_hrco_assignments pha ON pha.plantilla_id = p.id AND pha.is_active;

COMMENT ON VIEW public.v_plantilla_safe IS
  'Safe read-only view over plantilla. Excludes deleted, archived, expired deactivated-visibility, '
  'and expired inactive-visibility rows. LEFT JOIN stores exposes area_city and area_province. '
  'Adds append-only derived_employment_type from active store link count. Includes active HRCO assignments.';

-- 4. Recreate public.get_plantilla_employees to expose assigned HRCO info
DROP FUNCTION IF EXISTS public.get_plantilla_employees(uuid, text);

CREATE OR REPLACE FUNCTION public.get_plantilla_employees(
  p_store_id      uuid,
  p_status_filter text DEFAULT 'all'::text
)
RETURNS TABLE(
  id                        uuid,
  employee_name             text,
  employee_no               text,
  emploc_no                 text,
  vcode                     text,
  position_name             text,
  deployment_type           text,
  account                   text,
  store_name                text,
  status                    text,
  separation_status         text,
  inactive_at               timestamp with time zone,
  for_deactivation_at       timestamp with time zone,
  deactivated_at            timestamp with time zone,
  deactivated_visible_until timestamp with time zone,
  sla_status                text,
  sla_due_date              date,
  can_reassign_store        boolean,
  can_resign                boolean,
  can_endo                  boolean,
  can_separate              boolean,
  can_request_deactivation  boolean,
  can_complete_deactivation boolean,
  can_view_benefits         boolean,
  can_sync_mika             boolean,
  can_reveal_benefits       boolean,
  area_city                 text,
  area_province             text,
  derived_employment_type   text,
  assigned_hrco_user_id     uuid,
  assigned_hrco_name        text,
  assigned_hrco_email       text,
  assigned_hrco_date        timestamp with time zone
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role          text    := public.get_my_role();
  v_is_ops        boolean := public.i_am_ops();
  v_is_full       boolean := public.i_have_full_access();
  v_is_backoffice boolean := v_role IN ('Back Office', 'Backoffice');
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    p.employee_name,
    p.employee_no,
    p.emploc_no,
    p.vcode,
    p.position::text,
    p.deployment_type,
    p.account,
    p.store_name,
    p.status,
    p.separation_status,
    p.inactive_at,
    p.for_deactivation_at,
    p.deactivated_at,
    p.deactivated_visible_until,
    -- SLA status
    CASE
      WHEN p.status = 'Inactive' AND p.inactive_at < NOW() - INTERVAL '3 days'
        THEN 'breach_inactive_no_request'
      WHEN p.status = 'For Deactivation' AND p.for_deactivation_at < NOW() - INTERVAL '3 days'
        THEN 'breach_deactivation_overdue'
      WHEN p.status IN ('Inactive', 'For Deactivation') THEN 'within_sla'
      ELSE NULL
    END,
    -- SLA due date
    CASE
      WHEN p.status = 'Inactive'         THEN (p.inactive_at + INTERVAL '3 days')::date
      WHEN p.status = 'For Deactivation' THEN (p.for_deactivation_at + INTERVAL '3 days')::date
      ELSE NULL
    END,
    -- can_reassign_store: Active and On Leave employees
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_resign
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_endo
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_separate
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_request_deactivation: Inactive employees
    (v_is_full OR (v_is_ops AND p.status = 'Inactive')),
    -- can_complete_deactivation: Backoffice for For Deactivation
    ((v_is_backoffice OR v_is_full) AND p.status = 'For Deactivation'),
    true,
    (v_is_full OR v_is_ops OR v_is_backoffice),
    (v_is_full OR v_is_ops OR v_is_backoffice),
    s.area_city::text,
    COALESCE(s.area_province, s.province)::text,
    CASE
      WHEN (
        SELECT COUNT(*)
          FROM public.plantilla_store_links psl
         WHERE psl.plantilla_id = p.id
           AND psl.deleted_at IS NULL
           AND psl.status = 'Active'
      ) > 1
      THEN 'Roving'
      ELSE COALESCE(p.deployment_type, 'Stationary')
    END AS derived_employment_type,
    -- Assigned HRCO fields
    pha.hrco_user_id AS assigned_hrco_user_id,
    pha.hrco_name_snapshot AS assigned_hrco_name,
    pha.hrco_email_snapshot AS assigned_hrco_email,
    pha.effective_start AS assigned_hrco_date
  FROM public.plantilla p
  LEFT JOIN public.stores s ON s.id = p.store_id
  LEFT JOIN public.plantilla_hrco_assignments pha ON pha.plantilla_id = p.id AND pha.is_active
  WHERE p.store_id = p_store_id
    AND (
      v_is_full
      OR p.account = ANY (public.get_my_allowed_accounts())
    )
    AND (
      CASE LOWER(p_status_filter)
        WHEN 'all'              THEN p.status IN ('Active', 'On Leave', 'Inactive', 'For Deactivation', 'Deactivated')
                                     AND (p.status <> 'Deactivated'
                                          OR p.deactivated_visible_until > NOW())
        WHEN 'active'           THEN p.status IN ('Active', 'On Leave')
        WHEN 'inactive'         THEN p.status IN ('Inactive', 'Floating')
                                     AND p.source_headcount_request_id IS NULL
        WHEN 'for_deactivation' THEN p.status = 'For Deactivation'
        WHEN 'deactivated'      THEN p.status = 'Deactivated'
                                     AND p.deactivated_visible_until > NOW()
        ELSE true
      END
    )
  ORDER BY
    CASE p.status
      WHEN 'Active'             THEN 1
      WHEN 'On Leave'           THEN 2
      WHEN 'Inactive'           THEN 3
      WHEN 'For Deactivation'   THEN 4
      WHEN 'Deactivated'        THEN 5
      ELSE 6
    END,
    p.employee_name;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_plantilla_employees(uuid, text) TO authenticated;

COMMIT;
