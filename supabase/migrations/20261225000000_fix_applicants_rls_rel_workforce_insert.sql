-- Migration: 20261225000000_fix_applicants_rls_rel_workforce_insert.sql
-- Ticket: ohm#rlsrel06
-- Purpose:
--   Fix RLS regression where adding an applicant to REL-00006 (or any Reliever/
--   Commando/Bundler/Seasonal pool vacancy created via an Ops request) fails with:
--
--     PostgrestException: new row violates row-level security policy for table "applicants"
--     code 42501  details Forbidden
--
-- Root Cause:
--   The `applicants_insert_ops_only` policy (set in 20261215000005_moses_hq_workforce_request_approval)
--   only allows Recruitment to insert applicants for pool vacancies.  Ops users are blocked
--   because the Ops/Recruitment path (condition 3) explicitly guards
--     AND NOT COALESCE(v.is_pool_vacancy, false)
--   and the pool-vacancy arm (condition 2) only admits i_am_recruitment().
--
--   Ops-created pool vacancies (is_ops_request = true) are already visible to Ops users in
--   the Vacancy Open list via vacancies_read_scoped:
--     account = ANY(get_my_allowed_accounts())
--     AND (NOT is_pool_vacancy OR is_ops_request = true)
--   So Ops can SEE REL-00006 but CANNOT insert an applicant for it.
--
-- Fix:
--   Add a 4th condition (§4) that mirrors the visibility rule in vacancies_read_scoped:
--     i_am_ops()
--     AND is_pool_vacancy = true
--     AND is_ops_request = true              ← Data-Team direct pool vacancies remain off-limits to Ops
--     AND v.account = ANY(get_my_allowed_accounts())
--
--   This is strictly additive.  Existing conditions 1–3 are reproduced without change.
--   The closure guard (has_pending_closure) is preserved.
--
-- Safety:
--   • does NOT use USING (true) or WITH CHECK (true)
--   • does NOT grant blanket INSERT to authenticated
--   • does NOT drop the closure guard
--   • does NOT widen normal-vacancy Ops/Recruitment INSERT scope
--   • Data Team (Moses HQ) direct pool vacancies (is_ops_request = false) remain
--     restricted to Recruitment + full-access admins (conditions 2 + 1)
--   • Out-of-scope Ops users (account not in allowed_accounts) remain blocked
--   • Unauthorized roles (viewer, backofficePersonnel, hrPersonnel) remain blocked
--
-- DB Smoke Tests (run after applying migration on live DB):
--
--   §S1 — Scoped Ops user can insert applicant for an Ops pool vacancy in scope:
--     SET LOCAL request.jwt.claims = '{"role":"authenticated"}';
--     -- Simulate session for OM scoped to the relevant account
--     -- (run as that OM's user):
--     INSERT INTO public.applicants (
--       vacancy_vcode, last_name, first_name, full_name, status
--     ) VALUES (
--       'REL-GHQ-00006', 'Test', 'Applicant', 'Applicant Test', 'New'
--     );
--     -- Expected: INSERT 0 1 (success)
--     -- Then: DELETE FROM public.applicants WHERE vacancy_vcode='REL-GHQ-00006' AND last_name='Test';
--
--   §S2 — Out-of-scope Ops user is blocked:
--     -- Simulate session for OM NOT scoped to REL-GHQ-00006's account
--     INSERT INTO public.applicants (vacancy_vcode, last_name, first_name, full_name, status)
--     VALUES ('REL-GHQ-00006', 'Test', 'Blocked', 'Blocked Test', 'New');
--     -- Expected: ERROR 42501 new row violates row-level security policy
--
--   §S3 — Normal vacancy add applicant still works (Ops user, in scope):
--     INSERT INTO public.applicants (vacancy_vcode, last_name, first_name, full_name, status)
--     VALUES ('SOMEABC-001', 'Test', 'Normal', 'Normal Test', 'New');
--     -- Expected: INSERT 0 1 (success, unchanged behavior)
--
--   §S4 — Recruitment can add to any pool vacancy (unchanged):
--     -- Simulate session for recruitment user
--     INSERT INTO public.applicants (vacancy_vcode, last_name, first_name, full_name, status)
--     VALUES ('REL-GHQ-00006', 'Recruit', 'Test', 'Test Recruit', 'New');
--     -- Expected: INSERT 0 1 (success)
--
--   §S5 — Viewer / unauthorized user remains blocked:
--     -- Simulate session for viewer user
--     INSERT INTO public.applicants (vacancy_vcode, last_name, first_name, full_name, status)
--     VALUES ('REL-GHQ-00006', 'Unauth', 'Test', 'Test Unauth', 'New');
--     -- Expected: ERROR 42501

-- ── §1  Rebuild applicants INSERT policy with Ops pool-vacancy arm ──────────

DROP POLICY IF EXISTS "applicants_insert_ops_only" ON public.applicants;

CREATE POLICY "applicants_insert_ops_only" ON "public"."applicants"
FOR INSERT TO public
WITH CHECK (
  (
    -- Condition 1 (unchanged): Full-access admins (SA / HA) can insert for any vacancy.
    public.i_have_full_access()

    -- Condition 2 (unchanged): Recruitment can add applicants to any pool vacancy.
    OR (
      public.i_am_recruitment()
      AND EXISTS (
        SELECT 1 FROM public.vacancies v
        WHERE v.vcode = applicants.vacancy_vcode
          AND v.is_pool_vacancy = true
          AND v.deleted_at IS NULL
      )
    )

    -- Condition 3 (unchanged): Ops or Recruitment can add applicants to normal
    -- (non-pool) vacancies within their allowed account scope.
    OR (
      (public.i_am_ops() OR public.i_am_recruitment())
      AND vacancy_vcode IN (
        SELECT v.vcode
        FROM public.vacancies v
        WHERE v.account = ANY (public.get_my_allowed_accounts())
          AND v.deleted_at IS NULL
          AND NOT COALESCE(v.is_pool_vacancy, false)
      )
    )

    -- Condition 4 (NEW — ohm#rlsrel06):
    --   Ops users may add applicants to Ops-created pool vacancies (REL-00006,
    --   COM-GHQ-*, BUN-GHQ-*, SEA-GHQ-*) that are within their allowed account scope.
    --   Gate: is_ops_request = true ensures Data-Team direct pool vacancies
    --   (Moses HQ headcount, is_ops_request = false) remain restricted to
    --   Recruitment + full-access admins (conditions 2 + 1).
    --   Scope gate mirrors vacancies_read_scoped Ops visibility rule exactly:
    --     account = ANY(get_my_allowed_accounts())
    --     AND (NOT is_pool_vacancy OR is_ops_request = true)
    OR (
      public.i_am_ops()
      AND EXISTS (
        SELECT 1 FROM public.vacancies v
        WHERE v.vcode = applicants.vacancy_vcode
          AND v.is_pool_vacancy = true
          AND COALESCE(v.is_ops_request, false) = true
          AND v.account = ANY (public.get_my_allowed_accounts())
          AND v.deleted_at IS NULL
      )
    )
  )

  -- Closure guard (unchanged): never allow insert into a vacancy pending closure.
  AND NOT EXISTS (
    SELECT 1 FROM public.vacancies v
    WHERE v.vcode = applicants.vacancy_vcode
      AND v.has_pending_closure = true
      AND v.deleted_at IS NULL
  )
);

-- ── §2  Verify policy was created ────────────────────────────────────────────
--
--   SELECT polname, polcmd, polpermissive
--   FROM pg_policies
--   WHERE schemaname = 'public'
--     AND tablename = 'applicants'
--     AND polname = 'applicants_insert_ops_only';
--
--   Expected: 1 row, polcmd = 'INSERT', polpermissive = true
