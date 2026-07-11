-- ============================================================
-- OHM2026_2041 — Fix fn_update_applicant_profile_once RBAC
-- ============================================================
-- Problem: OHM2026_2037 (20260522000000) created the RPC but
--          excluded headAdmin from both the allowed-callers gate
--          and the one-time override bypass.
--
-- Business rule (corrected):
--   Allowed callers: Ops Team + Recruitment Team + Super Admin
--                    + Head Admin
--   One-time limit:  Non-full-access callers (anyone below headAdmin)
--   Override bypass: Super Admin AND Head Admin
--                    → edits after limit; does NOT increment counter
--   Lock gate:       confirmed_onboard / transferred / hired
--                    (covers Vacancy → HR Emploc → Plantilla pipeline)
--   Terminal statuses (rejected/failed/backout) remain editable
--                    while the applicant is still in Vacancy context.
--
-- Depends: 20260522000000 must be applied first (adds tracking
--          columns + applicant_profile_edit_history table).
--
-- Change surface:
--   - Replaces fn_update_applicant_profile_once signature only.
--   - No schema changes. No new tables. No RLS changes.
--   - Fully backward-compatible with existing audit table.
--   - is_super_admin_override column is preserved; semantics now
--     cover headAdmin overrides as well (documented in comment).
-- ============================================================

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
  -- i_have_full_access() = headAdmin (level 90) OR superAdmin (level 100)
  v_is_full_access boolean := public.i_have_full_access();
  v_profile_id     uuid    := public.get_my_profile_id();
  v_app            public.applicants%ROWTYPE;
  v_is_override    boolean := false;
  v_new_edit_count integer;

  -- Statuses that indicate the applicant has left Vacancy/Pipeline.
  -- confirmed_onboard → triggers move to HR Emploc.
  -- transferred / hired → moved to Plantilla or beyond.
  -- lower() tolerates mixed-case stored values.
  c_locked_statuses text[] := ARRAY[
    'confirmed_onboard', 'transferred', 'hired'
  ];
BEGIN
  -- ── RBAC ──────────────────────────────────────────────────────
  -- Allowed: Ops Team (40-70), Recruitment Team (20),
  --          Head Admin (90), Super Admin (100).
  -- Denied:  Encoder (30), HR Personnel (25), Backoffice (15),
  --          Viewer (10), and all others below headAdmin who are
  --          not Ops or Recruitment.
  IF NOT (
    public.i_am_ops()            -- levels 40-70
    OR public.i_am_recruitment() -- level 20
    OR v_is_full_access          -- headAdmin (90) OR superAdmin (100)
  ) THEN
    RAISE EXCEPTION
      'forbidden: Ops Team, Recruitment Team, Head Admin, or Super Admin required to edit applicant profile'
      USING ERRCODE = '42501';
  END IF;

  -- ── Required fields ────────────────────────────────────────────
  IF TRIM(COALESCE(p_first_name, '')) = '' THEN
    RAISE EXCEPTION 'p_first_name is required' USING ERRCODE = '22023';
  END IF;
  IF TRIM(COALESCE(p_last_name, '')) = '' THEN
    RAISE EXCEPTION 'p_last_name is required' USING ERRCODE = '22023';
  END IF;
  IF TRIM(COALESCE(p_contact_number, '')) = '' THEN
    RAISE EXCEPTION 'p_contact_number is required' USING ERRCODE = '22023';
  END IF;
  IF TRIM(COALESCE(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'p_reason (comments/reason) is required' USING ERRCODE = '22023';
  END IF;

  -- ── Fetch applicant ────────────────────────────────────────────
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
     AND COALESCE(is_archived, false) = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Scope check ────────────────────────────────────────────────
  -- Full-access users (headAdmin + superAdmin) bypass scope.
  IF NOT v_is_full_access THEN
    IF NOT EXISTS (
      SELECT 1
        FROM public.vacancies v
       WHERE v.vcode       = v_app.vacancy_vcode
         AND v.account     = ANY(public.get_my_allowed_accounts())
         AND v.deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION
        'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Lock check ─────────────────────────────────────────────────
  -- Locked once the applicant has progressed beyond Vacancy/Pipeline.
  -- Terminal Vacancy statuses (rejected/failed/backout) are NOT locked
  -- because the applicant record remains in the Vacancy context.
  -- Lock applies to ALL callers — no override for lock state.
  IF lower(COALESCE(v_app.status, '')) = ANY(c_locked_statuses) THEN
    RAISE EXCEPTION
      'applicant profile is locked: applicant has progressed beyond the Vacancy pipeline (status: %)',
      v_app.status
      USING ERRCODE = '22023';
  END IF;

  -- ── One-time enforcement ───────────────────────────────────────
  -- Full-access users (headAdmin + superAdmin) may edit after the
  -- one-time limit has been used. Regular callers (Ops/Recruitment)
  -- are blocked after their single edit.
  -- Note: is_super_admin_override column retains its name for schema
  -- compatibility; it now semantically covers headAdmin overrides too.
  IF COALESCE(v_app.profile_edit_count, 0) >= 1 THEN
    IF NOT v_is_full_access THEN
      RAISE EXCEPTION
        'one-time profile edit already used for applicant % — Head Admin or Super Admin override required',
        p_applicant_id
        USING ERRCODE = '22023';
    END IF;
    -- Full-access override path (headAdmin or superAdmin)
    v_is_override := true;
  END IF;

  -- ── Change detection ───────────────────────────────────────────
  -- Reject no-op calls where nothing actually differs.
  IF p_first_name IS NOT DISTINCT FROM v_app.first_name
     AND COALESCE(p_middle_name, '') = COALESCE(v_app.middle_name, '')
     AND p_last_name IS NOT DISTINCT FROM v_app.last_name
     AND p_contact_number IS NOT DISTINCT FROM v_app.contact_number
  THEN
    RAISE EXCEPTION
      'no field changes detected — at least one field must differ from current values'
      USING ERRCODE = '22023';
  END IF;

  -- ── Write immutable audit row ──────────────────────────────────
  -- Always logged regardless of caller role.
  -- is_super_admin_override = true for headAdmin OR superAdmin overrides.
  INSERT INTO public.applicant_profile_edit_history (
    applicant_id,
    edited_by,
    old_first_name,     new_first_name,
    old_middle_name,    new_middle_name,
    old_last_name,      new_last_name,
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

  -- ── Compute new edit count ─────────────────────────────────────
  -- Full-access overrides (headAdmin/superAdmin) do NOT increment
  -- the counter so the one-time gate stays intact for OPS/Recruitment
  -- after an admin override.
  v_new_edit_count := CASE
    WHEN v_is_full_access THEN COALESCE(v_app.profile_edit_count, 0)
    ELSE                       COALESCE(v_app.profile_edit_count, 0) + 1
  END;

  -- ── Apply field changes immediately ────────────────────────────
  -- full_name rebuilt as "LAST, FIRST MIDDLE" — same convention as
  -- fn_approve_applicant_profile_edit_request. Flutter name_formatter
  -- handles final display rendering.
  UPDATE public.applicants
  SET
    first_name             = p_first_name,
    middle_name            = p_middle_name,
    last_name              = p_last_name,
    contact_number         = p_contact_number,
    full_name              = TRIM(
                               p_last_name || ', ' || p_first_name
                               || CASE
                                    WHEN TRIM(COALESCE(p_middle_name, '')) NOT IN
                                         ('', 'NA', 'N/A', 'NONE', 'N.A.')
                                    THEN ' ' || p_middle_name
                                    ELSE ''
                                  END
                             ),
    profile_edit_count     = v_new_edit_count,
    last_profile_edited_at = now(),
    last_profile_edited_by = v_profile_id,
    updated_at             = now(),
    updated_by             = v_profile_id
  WHERE id = p_applicant_id;

  -- ── Return success payload ─────────────────────────────────────
  RETURN jsonb_build_object(
    'success',      true,
    'applicant_id', p_applicant_id,
    'is_override',  v_is_override,
    'edit_count',   v_new_edit_count,
    'updated_at',   now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_update_applicant_profile_once(uuid, text, text, text, text, text)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_update_applicant_profile_once IS
  'Direct one-time applicant profile edit (no approval required). '
  'Callers: Ops Team, Recruitment Team, Head Admin, Super Admin. '
  'Ops and Recruitment: limited to 1 edit (profile_edit_count). '
  'Head Admin and Super Admin: may override after the one-time limit; '
  'override does NOT increment profile_edit_count. '
  'is_super_admin_override = true for both headAdmin and superAdmin overrides. '
  'Locked when status is confirmed_onboard / transferred / hired. '
  'Terminal statuses (rejected/failed/backout) remain editable in Vacancy context. '
  'Always writes an immutable row to applicant_profile_edit_history. '
  'p_reason is required. '
  'Depends on: 20260522000000 (tracking columns + audit table).';


-- ============================================================
-- §1  VALIDATION SQL  (run manually in staging/test)
-- ============================================================

/*
────────────────────────────────────────────────────────────────
V1. Confirm RPC signature is updated (headAdmin note in comment)
────────────────────────────────────────────────────────────────
SELECT proname, pg_get_function_arguments(oid), obj_description(oid, 'pg_proc')
  FROM pg_proc
 WHERE proname = 'fn_update_applicant_profile_once'
   AND pronamespace = 'public'::regnamespace;

Expected: 1 row. Comment mentions Head Admin.
────────────────────────────────────────────────────────────────

V2. OPS user edits once — applicant updated immediately
────────────────────────────────────────────────────────────────
-- (Authenticate as OPS role user in test session)
SELECT public.fn_update_applicant_profile_once(
  '<test_applicant_id>',
  'Corrected',       -- p_first_name
  'Dela Cruz',       -- p_last_name
  '09171234567',     -- p_contact_number
  'M',               -- p_middle_name
  'Typo correction'  -- p_reason (required)
);
Expected: { "success": true, "is_override": false, "edit_count": 1 }

-- Confirm applicant row updated
SELECT first_name, last_name, full_name, profile_edit_count
  FROM public.applicants WHERE id = '<test_applicant_id>';
Expected: fields match inputs; profile_edit_count = 1.

-- Confirm audit row
SELECT old_first_name, new_first_name, is_super_admin_override, reason
  FROM public.applicant_profile_edit_history
 WHERE applicant_id = '<test_applicant_id>'
 ORDER BY edited_at DESC LIMIT 1;
Expected: old/new values present; is_super_admin_override = false.
────────────────────────────────────────────────────────────────

V3. OPS second edit fails
────────────────────────────────────────────────────────────────
-- (Same OPS session, same applicant — edit_count = 1)
SELECT public.fn_update_applicant_profile_once(
  '<test_applicant_id>', 'Second', 'Attempt', '09179999999',
  NULL, 'Second attempt'
);
Expected: EXCEPTION — 'one-time profile edit already used...'
────────────────────────────────────────────────────────────────

V4. Recruitment user edits once (same rules as OPS)
────────────────────────────────────────────────────────────────
-- (Authenticate as Recruitment role; fresh applicant edit_count = 0)
SELECT public.fn_update_applicant_profile_once(
  '<fresh_applicant_id>', 'Recr', 'Test', '09181111111',
  NULL, 'Recruitment correction'
);
Expected: { "success": true, "edit_count": 1, "is_override": false }
────────────────────────────────────────────────────────────────

V5. Head Admin overrides after one-time edit used
────────────────────────────────────────────────────────────────
-- (Authenticate as headAdmin; applicant already has edit_count = 1)
SELECT public.fn_update_applicant_profile_once(
  '<test_applicant_id>',
  'HeadFixed', 'Override', '09170000001',
  NULL, 'Head Admin override correction'
);
Expected: { "success": true, "is_override": true, "edit_count": 1 }
-- edit_count remains 1 (not incremented for headAdmin override)

SELECT is_super_admin_override
  FROM public.applicant_profile_edit_history
 WHERE applicant_id = '<test_applicant_id>'
 ORDER BY edited_at DESC LIMIT 1;
Expected: is_super_admin_override = true
────────────────────────────────────────────────────────────────

V6. Super Admin overrides after one-time edit used
────────────────────────────────────────────────────────────────
-- (Authenticate as superAdmin; applicant already has edit_count = 1)
SELECT public.fn_update_applicant_profile_once(
  '<test_applicant_id>',
  'AdminFixed', 'Override', '09170000000',
  NULL, 'Super Admin override correction'
);
Expected: { "success": true, "is_override": true, "edit_count": 1 }
────────────────────────────────────────────────────────────────

V7. Locked status blocks ALL callers (including headAdmin/superAdmin)
────────────────────────────────────────────────────────────────
-- Temporarily set test applicant to confirmed_onboard
UPDATE public.applicants
   SET status = 'confirmed_onboard'
 WHERE id = '<lock_test_applicant_id>';

-- Attempt edit as any role (Ops, Recruitment, headAdmin, superAdmin)
SELECT public.fn_update_applicant_profile_once(
  '<lock_test_applicant_id>', 'Locked', 'Attempt', '09170000001',
  NULL, 'Should fail'
);
Expected: EXCEPTION — 'applicant profile is locked...'
-- Same result for status = 'transferred' or 'hired'
-- Restore: UPDATE public.applicants SET status = '<original>' WHERE id = '...'
────────────────────────────────────────────────────────────────

V8. Terminal Vacancy statuses (backout/failed/rejected) remain editable
────────────────────────────────────────────────────────────────
-- Set applicant to backout status (still in Vacancy context)
UPDATE public.applicants
   SET status = 'backout', profile_edit_count = 0
 WHERE id = '<terminal_test_applicant_id>';

SELECT public.fn_update_applicant_profile_once(
  '<terminal_test_applicant_id>',
  'BackoutFixed', 'Name', '09172222222',
  NULL, 'Correcting before archival'
);
Expected: { "success": true, "edit_count": 1, "is_override": false }
────────────────────────────────────────────────────────────────

V9. p_reason required — empty reason fails
────────────────────────────────────────────────────────────────
SELECT public.fn_update_applicant_profile_once(
  '<test_applicant_id>', 'Test', 'Name', '09170000002',
  NULL, ''   -- empty reason
);
Expected: EXCEPTION — 'p_reason (comments/reason) is required'

SELECT public.fn_update_applicant_profile_once(
  '<test_applicant_id>', 'Test', 'Name', '09170000002',
  NULL, NULL  -- null reason
);
Expected: EXCEPTION — 'p_reason (comments/reason) is required'
────────────────────────────────────────────────────────────────

V10. Audit history is immutable (no UPDATE/DELETE via client)
────────────────────────────────────────────────────────────────
UPDATE public.applicant_profile_edit_history
   SET reason = 'tampered'
 WHERE applicant_id = '<test_applicant_id>';
Expected: 0 rows updated (RLS blocks it)

DELETE FROM public.applicant_profile_edit_history
 WHERE applicant_id = '<test_applicant_id>';
Expected: 0 rows deleted (RLS blocks it)
────────────────────────────────────────────────────────────────

V11. No-op call is rejected
────────────────────────────────────────────────────────────────
-- Fetch current applicant values, then call with identical values.
Expected: EXCEPTION — 'no field changes detected...'
────────────────────────────────────────────────────────────────

V12. Encoder / Viewer / Backoffice cannot call RPC
────────────────────────────────────────────────────────────────
-- (Authenticate as encoder / backofficePersonnel / viewer)
SELECT public.fn_update_applicant_profile_once(
  '<test_applicant_id>', 'Test', 'Name', '09170000003',
  NULL, 'Should fail'
);
Expected: EXCEPTION — 'forbidden: Ops Team, Recruitment Team, Head Admin, or Super Admin required...'
────────────────────────────────────────────────────────────────
*/
