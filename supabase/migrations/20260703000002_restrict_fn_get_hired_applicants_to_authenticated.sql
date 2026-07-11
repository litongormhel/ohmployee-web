-- ============================================================
-- ohm#7v2vm5be — Phase 2 / Step 6 Follow-up
-- Restrict fn_get_hired_applicants(p_vcode text) to authenticated only
-- ============================================================
-- CONTEXT:
--   fn_get_hired_applicants was first flagged in ohm#9x4p7mq2 (Step 6)
--   and re-confirmed unresolved in ohm#4r8n2wpx (Step 8, HIGH bucket)
--   as carrying an undocumented explicit `anon` EXECUTE grant.
--
-- INVESTIGATION (ohm#7v2vm5be):
--   - Function returns hired-applicant PII: full_name, contact_number,
--     hired_date/hired_at, group/account/position, plantilla state.
--   - Only call site: fetchHiredApplicants() in
--     lib/data/services/vacancy_service.dart, invoked exclusively from
--     VacancyScreen's Hired tab — an authenticated, in-app screen.
--   - No public/no-login page (applicant status-check or otherwise)
--     depends on this function anywhere in lib/ or the web app.
--   - The anon grant traces to a blanket
--     `GRANT EXECUTE ... TO anon, authenticated, service_role`
--     in the original migrations (20260522020000 /
--     20260522030000) — no comment, no anon-facing design intent.
--
-- DECISION: no legitimate anon caller exists. Revoke anon/PUBLIC
--   EXECUTE, retain authenticated + service_role. The function is
--   used broadly across Vacancy-facing roles (recruitment, ops,
--   hrco, atl, tl, encoder, headAdmin, superAdmin) via the shared
--   Hired tab, so generic `authenticated` is the correct grant floor
--   per rbac.md — no single sub-role owns this data exclusively.
--
-- NOT IN SCOPE: the function does not filter by
--   get_my_allowed_accounts() (no account/group scope filter in the
--   query body). This is a separate pre-existing gap, out of scope
--   for this grant-only pass per prompt instruction not to touch
--   any other behavior of the function. Flagged separately.
-- ============================================================

REVOKE EXECUTE ON FUNCTION public.fn_get_hired_applicants(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_get_hired_applicants(text) FROM anon;

GRANT EXECUTE ON FUNCTION public.fn_get_hired_applicants(text) TO authenticated;
