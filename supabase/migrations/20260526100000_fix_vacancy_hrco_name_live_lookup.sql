-- ============================================================
-- OHM2026_0053 — Fix Vacancy HRCO Name: Live Lookup
-- ============================================================
-- Root cause:
--   vacancies.hrco_name is a name snapshot set at vacancy
--   creation time.  vw_vacancy_list and vw_vacancy_detail
--   project v.hrco_name directly — no live role check.
--   After a user's role is changed via User Management, the
--   stale name persists in the view, so Vacancy cards continue
--   showing the former HRCO even when they no longer hold
--   that role.
--
-- Fix:
--   Both views now LEFT JOIN users_profile + roles on
--   vacancies.hrco_user_id.  hrco_name is returned only
--   when the referenced user is still active AND still holds
--   the HRCO role.  If either condition fails, hrco_name
--   returns NULL and the card renders — / blank as per the
--   existing Flutter null-display convention.
--
--   vacancies.hrco_user_id is preserved unchanged so that:
--   (a) the snapshot audit trail is intact,
--   (b) a future RPC can reassign or clear the HRCO link
--       without losing the FK reference.
--
-- No schema changes — DROP/CREATE view only.
-- Safe to apply standalone; no dependencies on pending
-- migrations (no applicant-status or HC-request content).
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- §1  vw_vacancy_detail — live HRCO role check
-- ─────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS public.vw_vacancy_detail;
CREATE VIEW public.vw_vacancy_detail AS
 WITH applicant_stats AS (
   SELECT a.vacancy_vcode,
     count(*) FILTER (
       WHERE COALESCE(a.is_archived, false) = false
         AND a.status <> ALL (ARRAY[
           'Failed'::text,'Backout'::text,
           'Did Not Report'::text,'Rejected by Ops'::text,
           'Confirmed Onboard'::text
         ])
     ) AS active_applicant_count,
     count(*) FILTER (
       WHERE COALESCE(a.is_archived, false) = false
         AND a.status = 'Confirmed Onboard'::text
     ) AS confirmed_onboard_count,
     max(a.hired_at) FILTER (
       WHERE COALESCE(a.is_archived, false) = false
         AND a.status = 'Confirmed Onboard'::text
     ) AS latest_hire_at,
     (count(*) FILTER (
       WHERE COALESCE(a.is_archived, false) = false
         AND a.status = 'Confirmed Onboard'::text
         AND COALESCE(a.hired_visible_until, a.hired_at + INTERVAL '7 days') > now()
     ) > 0) AS has_recent_hire
   FROM public.applicants a
   GROUP BY a.vacancy_vcode
 )
 SELECT
   v.id,
   v.vcode,
   v.account,
   v.account_id,
   v.store_name,
   v.store_id,
   v.area_name,
   v.area_city,
   v.province,
   v.store_branch,
   v.position,
   v.position_id,
   v.employment_type,
   v.status,
   CASE
     WHEN v.is_archived = true OR v.status = ANY (ARRAY['Closed'::text,'Archived'::text])
       THEN 'Archived'::text
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
   (CURRENT_DATE - v.vacant_date) AS aging_days,
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
   v.group_id,
   g.group_name,
   v.hrco_user_id,
   -- Live role check: return name only if user is still active HRCO.
   -- Returns NULL if the user was deactivated or their role was changed.
   CASE
     WHEN up_hrco.is_active = TRUE AND r_hrco.role_name = 'HRCO'
       THEN up_hrco.full_name
     ELSE NULL
   END AS hrco_name,
   COALESCE(up_trig.full_name, v.triggered_by_name) AS triggered_by_full_name,
   NULL::text AS triggered_by_role,
   vr.vacancy_type AS hc_request_type,
   vr.requested_by AS hc_request_requested_by,
   vr.requested_by_user_id AS hc_request_requested_by_user_id,
   vr.created_at AS hc_request_date_created,
   vr.no_of_slots AS hc_request_no_of_slots,
   COALESCE(s.has_recent_hire, false) AS has_recent_hire
 FROM public.vacancies v
   LEFT JOIN applicant_stats s       ON s.vacancy_vcode = v.vcode
   LEFT JOIN public.groups g         ON g.id = v.group_id
   LEFT JOIN public.users_profile up_trig  ON up_trig.id = v.triggered_by_user_id
   LEFT JOIN public.users_profile up_hrco  ON up_hrco.id = v.hrco_user_id
   LEFT JOIN public.roles r_hrco     ON r_hrco.id = up_hrco.role_id
   LEFT JOIN public.vacancy_requests vr ON vr.id = v.source_vacancy_request_id
 WHERE v.deleted_at IS NULL;

-- ─────────────────────────────────────────────────────────────
-- §2  vw_vacancy_list — live HRCO role check
-- ─────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS public.vw_vacancy_list;
CREATE VIEW public.vw_vacancy_list AS
 WITH applicant_stats AS (
   SELECT a.vacancy_vcode,
     count(*) FILTER (
       WHERE COALESCE(a.is_archived, false) = false
         AND a.status <> ALL (ARRAY[
           'Failed'::text,'Backout'::text,
           'Did Not Report'::text,'Rejected by Ops'::text,
           'Confirmed Onboard'::text
         ])
     ) AS active_applicant_count,
     count(*) FILTER (
       WHERE COALESCE(a.is_archived, false) = false
         AND a.status = 'Confirmed Onboard'::text
     ) AS confirmed_onboard_count,
     max(a.hired_at) FILTER (
       WHERE COALESCE(a.is_archived, false) = false
         AND a.status = 'Confirmed Onboard'::text
     ) AS latest_hire_at,
     (count(*) FILTER (
       WHERE COALESCE(a.is_archived, false) = false
         AND a.status = 'Confirmed Onboard'::text
         AND COALESCE(a.hired_visible_until, a.hired_at + INTERVAL '7 days') > now()
     ) > 0) AS has_recent_hire
   FROM public.applicants a
   GROUP BY a.vacancy_vcode
 )
 SELECT
   v.id,
   v.vcode,
   v.account,
   v.account_id,
   v.store_name,
   v.store_id,
   v.area_name,
   v.area_city,
   v.province,
   v.store_branch,
   v.position,
   v.position_id,
   v.employment_type,
   v.status,
   CASE
     WHEN v.is_archived = true OR v.status = ANY (ARRAY['Closed'::text,'Archived'::text])
       THEN 'Archived'::text
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
   (CURRENT_DATE - v.vacant_date) AS aging_days,
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
   v.group_id,
   g.group_name,
   v.hrco_user_id,
   -- Live role check: return name only if user is still active HRCO.
   -- Returns NULL if the user was deactivated or their role was changed.
   CASE
     WHEN up_hrco.is_active = TRUE AND r_hrco.role_name = 'HRCO'
       THEN up_hrco.full_name
     ELSE NULL
   END AS hrco_name,
   COALESCE(s.has_recent_hire, false) AS has_recent_hire
 FROM public.vacancies v
   LEFT JOIN applicant_stats s       ON s.vacancy_vcode = v.vcode
   LEFT JOIN public.groups g         ON g.id = v.group_id
   LEFT JOIN public.users_profile up_hrco  ON up_hrco.id = v.hrco_user_id
   LEFT JOIN public.roles r_hrco     ON r_hrco.id = up_hrco.role_id
 WHERE v.deleted_at IS NULL;

-- ─────────────────────────────────────────────────────────────
-- VALIDATION QUERIES (read-only — execute manually)
-- ─────────────────────────────────────────────────────────────
/*
-- V1: Views exist and have the expected hrco_name column
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('vw_vacancy_list', 'vw_vacancy_detail')
  AND column_name = 'hrco_name';
-- Expected: 2 rows, data_type = 'text'

-- V2: Former HRCO shows NULL in view after role change
-- (substitute a vcode belonging to a vacancy whose hrco_user_id
--  points to a user who is no longer role_name = 'HRCO')
SELECT vcode, hrco_user_id, hrco_name
FROM public.vw_vacancy_list
WHERE hrco_user_id IS NOT NULL
  AND hrco_name IS NULL
LIMIT 10;
-- Expected: rows where hrco_user_id is set but hrco_name = NULL
-- (these are vacancies whose assigned HRCO no longer holds the role)

-- V3: Active HRCO still visible in view
SELECT vcode, hrco_user_id, hrco_name
FROM public.vw_vacancy_list
WHERE hrco_user_id IS NOT NULL
  AND hrco_name IS NOT NULL
LIMIT 10;
-- Expected: rows where the referenced user is still active + HRCO role

-- V4: vacancies with no hrco_user_id still return NULL hrco_name
SELECT vcode, hrco_user_id, hrco_name
FROM public.vw_vacancy_list
WHERE hrco_user_id IS NULL
LIMIT 5;
-- Expected: hrco_name = NULL (unaffected)

-- V5: No other columns in vw_vacancy_list changed shape
SELECT COUNT(*) FROM public.vw_vacancy_list;
-- Expected: same row count as before migration

-- V6: vw_vacancy_detail integrity check
SELECT COUNT(*) FROM public.vw_vacancy_detail;
-- Expected: same row count as before migration
*/
