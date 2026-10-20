-- Migration: Fix Vacancy Account Group Resolution and Backfill
-- Version: 20262606000046
-- Description:
--   1. Backfill vacancies where group_id is null from public.accounts.
--   2. Add BEFORE INSERT OR UPDATE trigger on vacancies to inherit account's group_id when null.
--   3. Update vw_vacancy_list and vw_vacancy_detail to coalesce group_id and group_name from accounts/groups.

-- §1. Backfill vacancies group_id from linked accounts
UPDATE public.vacancies v
SET group_id = a.group_id
FROM public.accounts a
WHERE v.group_id IS NULL
  AND a.group_id IS NOT NULL
  AND (v.account_id = a.id OR lower(trim(v.account)) = lower(trim(a.account_name)));

-- §2. Auto-assignment trigger for future vacancy inserts / updates
CREATE OR REPLACE FUNCTION public.trg_fn_auto_assign_vacancy_group_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.group_id IS NULL THEN
    IF NEW.account_id IS NOT NULL THEN
      SELECT a.group_id INTO NEW.group_id
      FROM public.accounts a
      WHERE a.id = NEW.account_id;
    END IF;

    IF NEW.group_id IS NULL AND NEW.account IS NOT NULL AND btrim(NEW.account) <> '' THEN
      SELECT a.group_id INTO NEW.group_id
      FROM public.accounts a
      WHERE lower(trim(a.account_name)) = lower(trim(NEW.account))
      LIMIT 1;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_assign_vacancy_group_id ON public.vacancies;
CREATE TRIGGER trg_auto_assign_vacancy_group_id
  BEFORE INSERT OR UPDATE ON public.vacancies
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_fn_auto_assign_vacancy_group_id();

-- §3. Update vw_vacancy_list with robust account-to-group join
CREATE OR REPLACE VIEW public.vw_vacancy_list AS
 WITH applicant_stats AS (
          SELECT a.vacancy_vcode,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND (a.status <> ALL (ARRAY['Failed'::text, 'Backout'::text, 'Did Not Report'::text, 'Rejected by Ops'::text, 'Confirmed Onboard'::text]))) AS active_applicant_count,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text) AS confirmed_onboard_count,
            max(a.hired_at) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text) AS latest_hire_at,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text AND COALESCE(a.hired_visible_until, a.hired_at + '7 days'::interval) > now()) > 0 AS has_recent_hire
           FROM applicants a
          GROUP BY a.vacancy_vcode
        )
 SELECT v.id,
    v.vcode,
    v.account,
    v.account_id,
    v.store_name,
    v.store_id,
    v.area_name,
    v.area_city,
    v.province,
    v.store_branch,
    v."position",
    v.position_id,
    v.employment_type,
    v.status,
        CASE
            WHEN v.is_archived = true OR (v.status = ANY (ARRAY['Closed'::text, 'Archived'::text])) THEN 'Archived'::text
            WHEN v.status = 'Filled'::text THEN 'Hired'::text
            WHEN COALESCE(v.has_pending_closure, false) = true
                 OR LOWER(COALESCE(v.closure_request_status, '')) = 'pending'
                 OR LOWER(COALESCE(v.status, '')) IN ('closure', 'for_closure')
                 OR EXISTS (
                   SELECT 1 FROM public.vacancy_closure_requests vcr
                   WHERE vcr.vacancy_vcode = v.vcode AND LOWER(vcr.status) = 'pending'
                 ) THEN 'For Closure'::text
            WHEN COALESCE(s.active_applicant_count, 0::bigint) > 0 THEN 'Pipeline'::text
            ELSE 'Open'::text
        END AS derived_status,
    v.source,
    v.source_vacancy_request_id,
    v.source_plantilla_id,
    v.vacancy_type,
    v.urgency_level,
    v.target_fill_date,
    v.required_headcount AS hc_needed,
    v.triggered_by_user_id,
    v.triggered_by_name,
    v.vacant_date,
    CURRENT_DATE - v.vacant_date AS aging_days,
    v.created_at,
    v.created_by,
    v.updated_at,
    v.is_archived,
    v.archived_at,
    v.closure_request_status,
    v.has_pending_closure,
    COALESCE(s.active_applicant_count, 0::bigint) AS active_applicant_count,
    COALESCE(s.confirmed_onboard_count, 0::bigint) AS confirmed_onboard_count,
    s.latest_hire_at,
    v.assigned_encoder_id,
    COALESCE(v.group_id, a.group_id) AS group_id,
    COALESCE(g.group_name, ga.group_name) AS group_name,
    v.hrco_user_id,
        CASE
            WHEN up_hrco.is_active = true AND r_hrco.role_name = 'HRCO'::text THEN up_hrco.full_name
            ELSE NULL::text
        END AS hrco_name,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire
   FROM vacancies v
     LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
     LEFT JOIN accounts a ON a.id = v.account_id OR (v.account_id IS NULL AND lower(trim(a.account_name)) = lower(trim(v.account)))
     LEFT JOIN groups g ON g.id = v.group_id
     LEFT JOIN groups ga ON ga.id = a.group_id
     LEFT JOIN users_profile up_hrco ON up_hrco.id = v.hrco_user_id
     LEFT JOIN roles r_hrco ON r_hrco.id = up_hrco.role_id
  WHERE v.deleted_at IS NULL;

GRANT ALL ON public.vw_vacancy_list TO authenticated, postgres, service_role;

-- §4. Update vw_vacancy_detail with robust account-to-group join
CREATE OR REPLACE VIEW public.vw_vacancy_detail AS
 WITH applicant_stats AS (
          SELECT a.vacancy_vcode,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND (a.status <> ALL (ARRAY['Failed'::text, 'Did Not Report'::text, 'Rejected by Ops'::text, 'Confirmed Onboard'::text]))) AS active_applicant_count,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text) AS confirmed_onboard_count,
            max(a.hired_at) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text) AS latest_hire_at,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text AND COALESCE(a.hired_visible_until, a.hired_at + '7 days'::interval) > now()) > 0 AS has_recent_hire
           FROM public.applicants a
          GROUP BY a.vacancy_vcode
        )
 SELECT v.id,
    v.vcode,
    v.account,
    v.account_id,
    v.store_name,
    v.store_id,
    v.area_name,
    v.area_city,
    v.province,
    v.store_branch,
    v."position",
    v.position_id,
    v.employment_type,
    v.status,
    CASE
        WHEN v.is_archived = true OR (v.status = ANY (ARRAY['Closed'::text, 'Archived'::text])) THEN 'Archived'::text
        WHEN v.status = 'Filled'::text THEN 'Hired'::text
        WHEN COALESCE(s.active_applicant_count, 0::bigint) > 0 THEN 'Pipeline'::text
        ELSE 'Open'::text
    END AS derived_status,
    v.source,
    v.source_vacancy_request_id,
    v.source_plantilla_id,
    v.vacancy_type,
    v.urgency_level,
    v.target_fill_date,
    v.required_headcount AS hc_needed,
    v.triggered_by_user_id,
    v.triggered_by_name,
    v.vacant_date,
    CURRENT_DATE - v.vacant_date AS aging_days,
    v.created_at,
    v.created_by,
    v.updated_at,
    v.is_archived,
    v.archived_at,
    v.closure_request_status,
    v.has_pending_closure,
    COALESCE(s.active_applicant_count, 0::bigint) AS active_applicant_count,
    COALESCE(s.confirmed_onboard_count, 0::bigint) AS confirmed_onboard_count,
    s.latest_hire_at,
    v.assigned_encoder_id,
    v.has_reliever,
    v.reliever_name,
    v.requested_by_user_id,
    v.requested_date,
    COALESCE(v.group_id, a.group_id) AS group_id,
    COALESCE(g.group_name, ga.group_name) AS group_name,
    v.hrco_user_id,
    v.hrco_name,
    COALESCE(up.full_name, v.triggered_by_name) AS triggered_by_full_name,
    NULL::text AS triggered_by_role,
    vr.vacancy_type AS hc_request_type,
    vr.requested_by AS hc_request_requested_by,
    vr.requested_by_user_id AS hc_request_requested_by_user_id,
    vr.created_at AS hc_request_date_created,
    vr.no_of_slots AS hc_request_no_of_slots,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire,
    v.request_type
   FROM public.vacancies v
     LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
     LEFT JOIN public.accounts a ON a.id = v.account_id OR (v.account_id IS NULL AND lower(trim(a.account_name)) = lower(trim(v.account)))
     LEFT JOIN public.groups g ON g.id = v.group_id
     LEFT JOIN public.groups ga ON ga.id = a.group_id
     LEFT JOIN public.users_profile up ON up.id = v.triggered_by_user_id
     LEFT JOIN public.vacancy_requests vr ON vr.id = v.source_vacancy_request_id
  WHERE v.deleted_at IS NULL;

GRANT ALL ON public.vw_vacancy_detail TO authenticated, postgres, service_role;
