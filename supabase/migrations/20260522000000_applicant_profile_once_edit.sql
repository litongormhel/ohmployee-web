-- ============================================================
-- OHM2026_2037 — One-Time Applicant Profile Edit
-- ============================================================
-- Feature:  Allow OPS, Recruitment, and Super Admin to correct
--           applicant name/contact fields while the applicant
--           is still in the Vacancy/Pipeline context.
--           Regular users: one edit total per applicant.
--           Super Admin: unlimited overrides; logged separately.
--           No approval required. Every edit is immutably logged.
--
-- Depends:  applicants table (remote_schema), users_profile,
--           vacancies, and all public role-helper functions
--           (get_my_role_level, i_am_ops, i_am_recruitment,
--            i_have_full_access, get_my_profile_id,
--            get_my_allowed_accounts).
--           NOTE: 20260520700000 (applicant_backend_infra) need
--           NOT be applied first — this migration is self-contained.
--
-- New objects:
--   - applicants.profile_edit_count        integer  DEFAULT 0
--   - applicants.last_profile_edited_at    timestamptz
--   - applicants.last_profile_edited_by    uuid → users_profile
--   - TABLE  public.applicant_profile_edit_history
--   - FUNCTION public.fn_update_applicant_profile_once(...)
--
-- Additive and backward-compatible. No existing RPC contracts
-- are modified. No existing columns are removed or renamed.
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- §1  TRACKING COLUMNS ON applicants
--     Safe to re-run (ADD COLUMN IF NOT EXISTS is idempotent).
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.applicants
  ADD COLUMN IF NOT EXISTS profile_edit_count     integer     NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_profile_edited_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_profile_edited_by uuid        REFERENCES public.users_profile(id);

COMMENT ON COLUMN public.applicants.profile_edit_count IS
  'Number of times applicant profile fields have been edited via '
  'fn_update_applicant_profile_once. Super Admin overrides do NOT '
  'increment this counter.';

COMMENT ON COLUMN public.applicants.last_profile_edited_at IS
  'Timestamp of the most recent fn_update_applicant_profile_once call '
  '(both regular edits and Super Admin overrides).';

COMMENT ON COLUMN public.applicants.last_profile_edited_by IS
  'Profile ID of the user who last called fn_update_applicant_profile_once.';

-- ──────────────────────────────────────────────────────────────
-- §2  IMMUTABLE AUDIT TABLE
--     One row per fn_update_applicant_profile_once call.
--     No UPDATE or DELETE permitted (enforced by RLS below).
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.applicant_profile_edit_history (
  id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id            uuid        NOT NULL
                          REFERENCES public.applicants(id) ON DELETE CASCADE,
  edited_by               uuid        NOT NULL
                          REFERENCES public.users_profile(id),
  edited_at               timestamptz NOT NULL DEFAULT now(),

  -- Snapshots — old values as they existed BEFORE the edit
  old_first_name          text,
  old_middle_name         text,
  old_last_name           text,
  old_contact_number      text,

  -- New values applied by this edit
  new_first_name          text,
  new_middle_name         text,
  new_last_name           text,
  new_contact_number      text,

  reason                  text,

  -- true when Super Admin edited after a regular edit was already used
  is_super_admin_override boolean     NOT NULL DEFAULT false,

  source_module           text        NOT NULL DEFAULT 'vacancy'
);

COMMENT ON TABLE public.applicant_profile_edit_history IS
  'Immutable audit log for fn_update_applicant_profile_once. '
  'One row per call. No UPDATE/DELETE allowed. '
  'is_super_admin_override = true when the applicant already had '
  'profile_edit_count >= 1 at the time of a Super Admin edit.';

CREATE INDEX IF NOT EXISTS idx_apeh_applicant_id
  ON public.applicant_profile_edit_history (applicant_id, edited_at DESC);

CREATE INDEX IF NOT EXISTS idx_apeh_edited_by
  ON public.applicant_profile_edit_history (edited_by);

-- ──────────────────────────────────────────────────────────────
-- §3  ROW LEVEL SECURITY
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.applicant_profile_edit_history ENABLE ROW LEVEL SECURITY;

-- Full-access users (headAdmin + superAdmin) can read all history.
-- Scoped users can read history for applicants within their accounts.
CREATE POLICY "apeh_select_scoped"
  ON public.applicant_profile_edit_history
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR public.get_my_role_level() = 30  -- Encoder
    OR EXISTS (
      SELECT 1
        FROM public.applicants a
        JOIN public.vacancies  v ON v.vcode = a.vacancy_vcode
       WHERE a.id = applicant_profile_edit_history.applicant_id
         AND v.account = ANY(public.get_my_allowed_accounts())
         AND v.deleted_at IS NULL
    )
  );

-- Block INSERT from the client layer — only the SECURITY DEFINER RPC
-- may write rows. Service role retains full access.
CREATE POLICY "apeh_insert_blocked_for_client"
  ON public.applicant_profile_edit_history
  FOR INSERT TO authenticated
  WITH CHECK (false);

-- Immutable: no UPDATE or DELETE ever.
CREATE POLICY "apeh_update_blocked"
  ON public.applicant_profile_edit_history
  FOR UPDATE USING (false);

CREATE POLICY "apeh_delete_blocked"
  ON public.applicant_profile_edit_history
  FOR DELETE USING (false);

GRANT SELECT ON public.applicant_profile_edit_history TO authenticated;
GRANT ALL    ON public.applicant_profile_edit_history TO service_role;

-- ──────────────────────────────────────────────────────────────
-- §4  fn_update_applicant_profile_once
--
--   Inputs
--     p_applicant_id   uuid          — target applicant
--     p_first_name     text          — new first name (required)
--     p_last_name      text          — new last name  (required)
--     p_contact_number text          — new contact    (required)
--     p_middle_name    text DEFAULT NULL — new middle name (optional)
--     p_reason         text DEFAULT NULL — optional free-text reason
--
--   Returns  jsonb  {
--     success, applicant_id, is_override, edit_count, updated_at
--   }
--
--   Edit locks
--     Locked when applicant.status IN
--       ('confirmed_onboard','transferred','hired')
--     meaning the applicant has progressed beyond Vacancy/Pipeline.
--
--   One-time rule
--     profile_edit_count >= 1  AND  caller is NOT Super Admin  → reject.
--     profile_edit_count >= 1  AND  caller IS Super Admin      → allow,
--       audit as is_super_admin_override = true,
--       do NOT increment profile_edit_count.
--
--   Audit
--     Always inserts one row into applicant_profile_edit_history.
--     applicant.full_name is rebuilt in the same LAST, FIRST MIDDLE
--     format used by fn_approve_applicant_profile_edit_request.
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_update_applicant_profile_once(
  p_applicant_id   uuid,
  p_first_name     text,
  p_last_name      text,
  p_contact_number text,
  p_middle_name    text DEFAULT NULL,
  p_reason         text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level          int     := COALESCE(public.get_my_role_level(), 0);
  v_profile_id     uuid    := public.get_my_profile_id();
  v_is_super_admin boolean := (v_level = 100);
  v_app            public.applicants%ROWTYPE;
  v_is_override    boolean := false;
  v_new_edit_count integer;

  -- Statuses that indicate the applicant has left the Vacancy pipeline.
  -- Comparison uses lower() to tolerate mixed-case stored values.
  c_locked_statuses text[] := ARRAY[
    'confirmed_onboard', 'transferred', 'hired'
  ];
BEGIN
  -- ── RBAC ──────────────────────────────────────────────────
  -- Allowed: Ops Team (level 40-70), Recruitment Team (level 20),
  --          Super Admin (level 100).
  -- Denied:  Head Admin (90), Encoder (30), HR Personnel (25),
  --          Backoffice (15), Viewer (10), and all others.
  IF NOT (
    public.i_am_ops()           -- levels 40-70
    OR public.i_am_recruitment() -- level 20
    OR v_is_super_admin          -- level 100
  ) THEN
    RAISE EXCEPTION
      'forbidden: Ops Team, Recruitment Team, or Super Admin required to edit applicant profile'
      USING ERRCODE = '42501';
  END IF;

  -- ── Required fields ────────────────────────────────────────
  IF TRIM(COALESCE(p_first_name, '')) = '' THEN
    RAISE EXCEPTION 'p_first_name is required' USING ERRCODE = '22023';
  END IF;
  IF TRIM(COALESCE(p_last_name, '')) = '' THEN
    RAISE EXCEPTION 'p_last_name is required' USING ERRCODE = '22023';
  END IF;
  IF TRIM(COALESCE(p_contact_number, '')) = '' THEN
    RAISE EXCEPTION 'p_contact_number is required' USING ERRCODE = '22023';
  END IF;

  -- ── Fetch applicant ────────────────────────────────────────
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
     AND COALESCE(is_archived, false) = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Scope check ────────────────────────────────────────────
  -- Full-access users (headAdmin + superAdmin) bypass scope.
  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1
        FROM public.vacancies v
       WHERE v.vcode        = v_app.vacancy_vcode
         AND v.account      = ANY(public.get_my_allowed_accounts())
         AND v.deleted_at  IS NULL
    ) THEN
      RAISE EXCEPTION
        'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Lock check ─────────────────────────────────────────────
  -- Applicant must still be in Vacancy/Pipeline context.
  -- Once confirmed_onboard / transferred / hired, no edits allowed
  -- even for Super Admin (the record is no longer a Vacancy concern).
  IF lower(COALESCE(v_app.status, '')) = ANY(c_locked_statuses) THEN
    RAISE EXCEPTION
      'applicant profile is locked: applicant has progressed beyond the Vacancy pipeline (status: %)',
      v_app.status
      USING ERRCODE = '22023';
  END IF;

  -- ── One-time enforcement ───────────────────────────────────
  IF COALESCE(v_app.profile_edit_count, 0) >= 1 THEN
    IF NOT v_is_super_admin THEN
      RAISE EXCEPTION
        'one-time profile edit already used for applicant % — Super Admin override required',
        p_applicant_id
        USING ERRCODE = '22023';
    END IF;
    -- Super Admin override path
    v_is_override := true;
  END IF;

  -- ── Change detection ───────────────────────────────────────
  -- Reject no-op calls where nothing actually differs.
  IF p_first_name     IS NOT DISTINCT FROM v_app.first_name
     AND COALESCE(p_middle_name, '')   = COALESCE(v_app.middle_name, '')
     AND p_last_name  IS NOT DISTINCT FROM v_app.last_name
     AND p_contact_number IS NOT DISTINCT FROM v_app.contact_number
  THEN
    RAISE EXCEPTION
      'no field changes detected — at least one field must differ from current values'
      USING ERRCODE = '22023';
  END IF;

  -- ── Write immutable audit row ──────────────────────────────
  INSERT INTO public.applicant_profile_edit_history (
    applicant_id,
    edited_by,
    old_first_name,    new_first_name,
    old_middle_name,   new_middle_name,
    old_last_name,     new_last_name,
    old_contact_number, new_contact_number,
    reason,
    is_super_admin_override,
    source_module
  ) VALUES (
    p_applicant_id,
    v_profile_id,
    v_app.first_name,     p_first_name,
    v_app.middle_name,    p_middle_name,
    v_app.last_name,      p_last_name,
    v_app.contact_number, p_contact_number,
    p_reason,
    v_is_override,
    'vacancy'
  );

  -- ── Compute new edit count ─────────────────────────────────
  -- Super Admin overrides do NOT increment the counter so that the
  -- "one-time used" gate remains intact for regular users afterward.
  v_new_edit_count := CASE
    WHEN v_is_super_admin THEN COALESCE(v_app.profile_edit_count, 0)
    ELSE                       COALESCE(v_app.profile_edit_count, 0) + 1
  END;

  -- ── Apply field changes ────────────────────────────────────
  -- full_name is rebuilt as "LAST, FIRST MIDDLE" (same convention as
  -- fn_approve_applicant_profile_edit_request). The Flutter formatter
  -- in name_formatter.dart handles the final display rendering.
  UPDATE public.applicants
  SET
    first_name              = p_first_name,
    middle_name             = p_middle_name,
    last_name               = p_last_name,
    contact_number          = p_contact_number,
    full_name               = TRIM(
                                p_last_name || ', ' || p_first_name
                                || CASE
                                     WHEN TRIM(COALESCE(p_middle_name, '')) NOT IN
                                          ('', 'NA', 'N/A', 'NONE', 'N.A.')
                                     THEN ' ' || p_middle_name
                                     ELSE ''
                                   END
                              ),
    profile_edit_count      = v_new_edit_count,
    last_profile_edited_at  = now(),
    last_profile_edited_by  = v_profile_id,
    updated_at              = now(),
    updated_by              = v_profile_id
  WHERE id = p_applicant_id;

  -- ── Return success payload ─────────────────────────────────
  RETURN jsonb_build_object(
    'success',        true,
    'applicant_id',   p_applicant_id,
    'is_override',    v_is_override,
    'edit_count',     v_new_edit_count,
    'updated_at',     now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_update_applicant_profile_once(uuid, text, text, text, text, text)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_update_applicant_profile_once IS
  'One-time direct profile edit for applicants still in Vacancy/Pipeline. '
  'Callers: Ops Team, Recruitment Team, Super Admin. '
  'Regular users limited to 1 edit (profile_edit_count). '
  'Super Admin may override after the one-time limit; does not increment counter. '
  'Always writes an immutable row to applicant_profile_edit_history. '
  'Locked when applicant status is confirmed_onboard / transferred / hired.';


-- ============================================================
-- §5  VALIDATION SQL  (run manually to confirm correctness)
--     Execute each block in a test/staging environment.
--     All results noted below are expected outcomes.
-- ============================================================

/*
────────────────────────────────────────────────────────────────
V1. Confirm tracking columns were added to applicants
────────────────────────────────────────────────────────────────
SELECT column_name, data_type, column_default, is_nullable
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name   = 'applicants'
   AND column_name  IN (
     'profile_edit_count',
     'last_profile_edited_at',
     'last_profile_edited_by'
   )
 ORDER BY column_name;

Expected: 3 rows.
  profile_edit_count     | integer  | 0      | NO
  last_profile_edited_at | timestamp with tz | NULL | YES
  last_profile_edited_by | uuid     | NULL   | YES
────────────────────────────────────────────────────────────────

V2. Confirm audit table exists with correct columns
────────────────────────────────────────────────────────────────
SELECT column_name, data_type
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name   = 'applicant_profile_edit_history'
 ORDER BY ordinal_position;

Expected: id, applicant_id, edited_by, edited_at, old_first_name,
          old_middle_name, old_last_name, old_contact_number,
          new_first_name, new_middle_name, new_last_name,
          new_contact_number, reason, is_super_admin_override,
          source_module.
────────────────────────────────────────────────────────────────

V3. Confirm RPC is registered with correct signature
────────────────────────────────────────────────────────────────
SELECT proname, pg_get_function_arguments(oid)
  FROM pg_proc
 WHERE proname = 'fn_update_applicant_profile_once'
   AND pronamespace = 'public'::regnamespace;

Expected: 1 row with arguments:
  p_applicant_id uuid,
  p_first_name text,
  p_last_name text,
  p_contact_number text,
  p_middle_name text DEFAULT NULL::text,
  p_reason text DEFAULT NULL::text
────────────────────────────────────────────────────────────────

V4. OPS user can edit once
────────────────────────────────────────────────────────────────
-- (Authenticate as an OPS-role user in a test session)
SELECT public.fn_update_applicant_profile_once(
  '<test_applicant_id>',
  'Corrected',      -- p_first_name
  'Dela Cruz',      -- p_last_name
  '09171234567',    -- p_contact_number
  'M',              -- p_middle_name
  'Typo correction' -- p_reason
);

Expected: { "success": true, "is_override": false, "edit_count": 1, ... }

-- Verify applicant row updated
SELECT first_name, last_name, middle_name, contact_number, full_name,
       profile_edit_count, last_profile_edited_at
  FROM public.applicants
 WHERE id = '<test_applicant_id>';

Expected: fields match inputs; profile_edit_count = 1.

-- Verify audit row
SELECT * FROM public.applicant_profile_edit_history
 WHERE applicant_id = '<test_applicant_id>'
 ORDER BY edited_at DESC LIMIT 1;

Expected: old values preserved, new values present,
          is_super_admin_override = false.
────────────────────────────────────────────────────────────────

V5. OPS second edit is rejected
────────────────────────────────────────────────────────────────
-- (Same OPS session, same applicant)
SELECT public.fn_update_applicant_profile_once(
  '<test_applicant_id>',
  'Second',
  'Attempt',
  '09179999999'
);

Expected: EXCEPTION — 'one-time profile edit already used...'
────────────────────────────────────────────────────────────────

V6. Recruitment user can edit once (same rules as OPS)
────────────────────────────────────────────────────────────────
-- (Authenticate as Recruitment role, use a fresh applicant with
--  profile_edit_count = 0)
SELECT public.fn_update_applicant_profile_once(
  '<fresh_applicant_id>',
  'Recr',
  'Test',
  '09181111111'
);

Expected: { "success": true, "edit_count": 1, "is_override": false }
────────────────────────────────────────────────────────────────

V7. Super Admin can override after one-time edit used
────────────────────────────────────────────────────────────────
-- (Authenticate as Super Admin, applicant already has edit_count = 1)
SELECT public.fn_update_applicant_profile_once(
  '<test_applicant_id>',    -- already has profile_edit_count = 1
  'AdminFixed',
  'Override',
  '09170000000',
  NULL,
  'Super Admin override correction'
);

Expected: { "success": true, "is_override": true,
            "edit_count": 1, ... }
-- edit_count remains 1 (not incremented for SA override)

-- Verify audit row is_super_admin_override = true
SELECT is_super_admin_override
  FROM public.applicant_profile_edit_history
 WHERE applicant_id = '<test_applicant_id>'
 ORDER BY edited_at DESC LIMIT 1;

Expected: is_super_admin_override = true
────────────────────────────────────────────────────────────────

V8. Confirmed Onboard applicant is locked
────────────────────────────────────────────────────────────────
-- Temporarily set an applicant to confirmed_onboard status
UPDATE public.applicants
   SET status = 'confirmed_onboard'
 WHERE id = '<lock_test_applicant_id>';

-- Attempt edit (any role)
SELECT public.fn_update_applicant_profile_once(
  '<lock_test_applicant_id>',
  'Locked',
  'Attempt',
  '09170000001'
);

Expected: EXCEPTION — 'applicant profile is locked...'
-- Same expected result for status = 'transferred' or 'hired'
────────────────────────────────────────────────────────────────

V9. Audit history is immutable (no UPDATE/DELETE via client)
────────────────────────────────────────────────────────────────
-- Attempt UPDATE (as an authenticated user, not service_role)
UPDATE public.applicant_profile_edit_history
   SET reason = 'tampered'
 WHERE applicant_id = '<test_applicant_id>';

Expected: 0 rows updated (RLS policy blocks it silently)

DELETE FROM public.applicant_profile_edit_history
 WHERE applicant_id = '<test_applicant_id>';

Expected: 0 rows deleted (RLS policy blocks it silently)
────────────────────────────────────────────────────────────────

V10. No-op call is rejected
────────────────────────────────────────────────────────────────
-- Fetch current values first, then call RPC with identical values.
-- Expected: EXCEPTION — 'no field changes detected...'
────────────────────────────────────────────────────────────────
*/
