-- ─────────────────────────────────────────────────────────────────────────────
-- OHM2026_1132: Smoke Tests — Read-Only Emergency Mode Enforcement
-- Vacancy Add Applicant / Update Applicant Status
--
-- Run these in the Supabase SQL Editor after applying migration
-- 20260614000001_web_vacancy_applicant_freeze_enforcement.sql.
-- For tests T4–T6, switch to an OM user session first.
-- ─────────────────────────────────────────────────────────────────────────────

-- T1. Confirm trigger exists on applicants table.
SELECT tgname, tgtype, tgenabled
FROM pg_trigger
WHERE tgrelid = 'public.applicants'::regclass
  AND tgname = 'trg_applicants_read_only_check';
-- Expected: 1 row, tgenabled = 'O' (enabled)

-- T2. Confirm RLS policies are updated (should list both with freeze guard).
SELECT polname, polcmd
FROM pg_policy
WHERE polrelid = 'public.applicants'::regclass
  AND polname IN ('applicants_insert_ops_only', 'applicants_update_ops_recruitment');
-- Expected: 2 rows

-- T3. Confirm get_web_freeze_mode_status RPC exists.
SELECT proname
FROM pg_proc
WHERE proname = 'get_web_freeze_mode_status'
  AND pronamespace = 'public'::regnamespace;
-- Expected: 1 row

-- T4. With read_only_emergency INACTIVE: verify function returns false.
SELECT public.get_web_freeze_mode_status();
-- Expected: { "is_read_only_emergency_active": false, ... }

-- ── Activate freeze for the following tests (SA only) ────────────────────────
-- SELECT public.fn_update_freeze_mode(
--   'read_only_emergency', true,
--   'OHM2026_1132 enforcement smoke test', '<your_sa_profile_id>'
-- );

-- T5. With read_only_emergency ACTIVE: verify function returns true.
SELECT public.get_web_freeze_mode_status();
-- Expected: { "is_read_only_emergency_active": true, "reason": "OHM2026_1132 enforcement smoke test", ... }

-- T6. With read_only_emergency ACTIVE, as OM session, Add Applicant must fail.
-- Replace <vacancy_uuid> with an actual vacancy id scoped to the OM account.
SELECT public.create_applicant_and_link_to_vacancy(
  '<vacancy_uuid>',
  'TestLastName',
  'TestFirstName',
  'TestMiddleName',
  '09000000000',
  CURRENT_DATE
);
-- Expected: ERROR P0001 "Read-Only Emergency Mode is active. Write actions are temporarily disabled."

-- T7. With read_only_emergency ACTIVE, Update Applicant Status must fail.
-- Replace <applicant_uuid> with an actual applicant id.
SELECT public.fn_update_applicant_status(
  '<applicant_uuid>',
  'for_interview',
  'Freeze mode smoke test'
);
-- Expected: ERROR P0001 "Read-Only Emergency Mode is active. Write actions are temporarily disabled."

-- T8. Direct INSERT on applicants must fail when freeze is active.
INSERT INTO public.applicants (vacancy_vcode, last_name, first_name, middle_name, contact_number)
VALUES ('SMOKE-0001', 'Test', 'OM', 'Blocked', '09000000000');
-- Expected: RLS denial (new policy WITH CHECK returns false when freeze is active)

-- ── Deactivate freeze after smoke test (SA only) ─────────────────────────────
-- SELECT public.fn_update_freeze_mode(
--   'read_only_emergency', false,
--   'OHM2026_1132 enforcement smoke test complete', '<your_sa_profile_id>'
-- );

-- T9. After deactivation, verify OM can insert applicant again (normal path).
-- Re-run T6 after deactivating freeze.
-- Expected: success / applicant inserted.
