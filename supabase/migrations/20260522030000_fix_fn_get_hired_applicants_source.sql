-- ============================================================
-- OHM2026_2044 — Fix Hired Tab Source for fn_get_hired_applicants
-- ============================================================
-- ROOT CAUSE:
--   fn_get_hired_applicants (OHM2026_2043) WHERE clause relied
--   exclusively on:
--     a.status = 'Confirmed Onboard'
--     AND COALESCE(a.hired_visible_until, a.hired_at + INTERVAL '7 days') > NOW()
--
--   This caused two failure modes:
--
--   1. Legacy applicants confirmed before the hired_at column was
--      introduced have hired_date set but hired_at = NULL and
--      hired_visible_until = NULL. The COALESCE evaluates to NULL,
--      so NULL > NOW() = FALSE — they never appear in the Hired Tab
--      despite being correctly approved and visible in HR Emploc.
--
--   2. The visibility window was 7 days (legacy default). The
--      required window is 15 days.
--
-- CHANGES (ALL ADDITIVE / REPLACE-OR-UPDATE ONLY):
--   §1  Backfill: set hired_visible_until for all existing hired
--       applicants where it is currently NULL.
--       Uses hired_at if present; falls back to hired_date cast to
--       timestamptz; falls back to NOW() as a safe sentinel.
--
--   §2  Replace trg_fn_set_hired_visible_until:
--       - Window extended from 7 → 15 days.
--       - Broadened trigger condition: fires on status transition to
--         'Confirmed Onboard' (main confirm_applicant_onboard path)
--         OR when hired_at is first set (alternative approval paths).
--
--   §3  Replace fn_get_hired_applicants:
--       Fixed WHERE clause:
--         - Remove status = 'Confirmed Onboard' dependency.
--         - Include any applicant where hired_at IS NOT NULL
--           OR hired_date IS NOT NULL (authoritative hire markers).
--         - Use hired_visible_until > NOW() explicitly (not the
--           COALESCE fallback) — §1 backfill ensures it is set.
--
-- NO CHANGES TO:
--   - Open/Pipeline classification logic
--   - confirm_applicant_onboard or endorse_applicant_to_ops RPCs
--   - HR Emploc workflow or move_to_plantilla
--   - RLS policies
--   - Vacancy module derived_status / active_applicant_count
--   - State field logic (Plantilla / HR Emploc / Vacancy)
--   - Any existing RPC contracts
-- ============================================================

-- ============================================================
-- §1  BACKFILL hired_visible_until (15 days)
--     Targets non-archived applicants that have a hire marker
--     (hired_at OR hired_date) but no hired_visible_until set.
--     Safe to re-run — WHERE hired_visible_until IS NULL is
--     idempotent.
-- ============================================================

UPDATE public.applicants
SET
  hired_visible_until = (
    COALESCE(
      hired_at,
      (hired_date)::timestamptz,
      NOW()
    ) + INTERVAL '15 days'
  ),
  updated_at = NOW()
WHERE
  (hired_at IS NOT NULL OR hired_date IS NOT NULL)
  AND hired_visible_until IS NULL
  AND COALESCE(is_archived, false) = false;

-- ============================================================
-- §2  REPLACE trg_fn_set_hired_visible_until
--     Extended to 15-day window.
--     Fires on:
--       a) Status transition TO 'Confirmed Onboard'
--          (main confirm_applicant_onboard approval path).
--       b) hired_at is newly populated from NULL
--          (alternative / future approval paths).
--     Does NOT overwrite an already-set hired_visible_until unless
--     the applicant is being freshly confirmed (condition a fires).
-- ============================================================

CREATE OR REPLACE FUNCTION public.trg_fn_set_hired_visible_until()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF (
    -- Path A: transitioning INTO 'Confirmed Onboard'
    -- Always refreshes hired_visible_until on a fresh confirmation.
    (
      NEW.status = 'Confirmed Onboard'
      AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'Confirmed Onboard')
    )
    OR
    -- Path B: hired_at is being set for the first time.
    -- Catches any alternative approval path that populates hired_at
    -- directly without setting status = 'Confirmed Onboard'.
    (
      NEW.hired_at IS NOT NULL
      AND (TG_OP = 'INSERT' OR OLD.hired_at IS DISTINCT FROM NEW.hired_at)
    )
  ) THEN
    NEW.hired_visible_until :=
      COALESCE(NEW.hired_at, NOW()) + INTERVAL '15 days';
  END IF;
  RETURN NEW;
END;
$$;

-- Recreate trigger (DROP IF EXISTS is safe — idempotent).
DROP TRIGGER IF EXISTS trg_set_hired_visible_until ON public.applicants;
CREATE TRIGGER trg_set_hired_visible_until
  BEFORE INSERT OR UPDATE ON public.applicants
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_fn_set_hired_visible_until();

-- ============================================================
-- §3  REPLACE fn_get_hired_applicants
--     Fixed WHERE clause:
--       - No longer relies on status = 'Confirmed Onboard'.
--       - Uses hired_at IS NOT NULL OR hired_date IS NOT NULL
--         as the authoritative hire marker.
--       - hired_visible_until > NOW() enforces the 15-day window.
--         The §1 backfill ensures all existing hired applicants
--         have this field populated, so the explicit check is safe.
--     State field logic unchanged:
--       Plantilla → HR Emploc → Vacancy / Pending HR Emploc.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_get_hired_applicants(p_vcode text DEFAULT NULL)
RETURNS TABLE (
  id                  uuid,
  vacancy_vcode       text,
  full_name           text,
  last_name           text,
  first_name          text,
  middle_name         text,
  contact_number      text,
  status              text,
  hired_date          date,
  hired_by            text,
  hired_by_team       text,
  hired_at            timestamp with time zone,
  hired_visible_until timestamp with time zone,
  days_remaining      integer,
  group_name          text,
  account             text,
  position_name       text,
  state               text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    a.id,
    a.vacancy_vcode,
    a.full_name,
    a.last_name,
    a.first_name,
    a.middle_name,
    a.contact_number,
    a.status,
    a.hired_date,
    a.hired_by,
    a.hired_by_team,
    a.hired_at,
    a.hired_visible_until,
    GREATEST(
      0,
      CEIL(
        EXTRACT(EPOCH FROM (a.hired_visible_until - NOW())) / 86400
      )::integer
    ) AS days_remaining,
    COALESCE(g.group_name, 'Group') AS group_name,
    v.account,
    v.position AS position_name,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM public.plantilla p
        WHERE p.hr_emploc_id = he.id
           OR (p.vcode = a.vacancy_vcode AND p.employee_name = a.full_name)
      ) THEN 'Plantilla'
      WHEN he.id IS NOT NULL THEN 'HR Emploc'
      ELSE 'Vacancy / Pending HR Emploc'
    END AS state
  FROM public.applicants a
  JOIN  public.vacancies   v  ON v.vcode = a.vacancy_vcode
  LEFT JOIN public.groups  g  ON g.id    = v.group_id
  LEFT JOIN public.hr_emploc he
         ON he.applicant_id = a.id
        AND he.deleted_at IS NULL
  -- ── FIXED WHERE CLAUSE ─────────────────────────────────
  -- Hire markers: at least one must be present.
  -- Does NOT rely on status = 'Confirmed Onboard' — covers
  -- all approval paths and legacy statuses ('Hired', etc.).
  WHERE COALESCE(a.is_archived, false) = false
    AND (a.hired_at IS NOT NULL OR a.hired_date IS NOT NULL)
    AND a.hired_visible_until > NOW()
    AND (p_vcode IS NULL OR a.vacancy_vcode = p_vcode)
  ORDER BY a.hired_at DESC NULLS LAST, a.hired_date DESC NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_hired_applicants(text)
  TO anon, authenticated, service_role;

-- ============================================================
-- VALIDATION (run manually in Supabase SQL Editor after apply)
-- ============================================================
--
-- V1: Confirm backfill applied — no hired applicant should have
--     hired_visible_until = NULL after §1.
-- SELECT COUNT(*) AS still_null
-- FROM public.applicants
-- WHERE (hired_at IS NOT NULL OR hired_date IS NOT NULL)
--   AND hired_visible_until IS NULL
--   AND COALESCE(is_archived, false) = false;
-- Expected: 0
--
-- V2: Confirm trigger function now uses 15-day window.
-- SELECT prosrc FROM pg_proc
-- WHERE proname = 'trg_fn_set_hired_visible_until';
-- Expected body contains: INTERVAL '15 days'
--
-- V3: Confirm trigger still present on applicants table.
-- SELECT tgname, tgenabled FROM pg_trigger
-- JOIN pg_class ON pg_class.oid = pg_trigger.tgrelid
-- WHERE relname = 'applicants' AND tgname = 'trg_set_hired_visible_until';
-- Expected: 1 row, tgenabled = 'O' (enabled)
--
-- V4: Approve an applicant via confirm_applicant_onboard.
--     Then verify:
-- SELECT id, status, hired_at, hired_date, hired_visible_until,
--        hired_visible_until - hired_at AS window
-- FROM public.applicants
-- WHERE id = '<newly_confirmed_applicant_id>';
-- Expected:
--   status              = 'Confirmed Onboard'
--   hired_at            IS NOT NULL
--   hired_date          IS NOT NULL
--   hired_visible_until = hired_at + 15 days (±1s)
--   window              ≈ '15 days'
--
-- V5: Confirm applicant appears in Hired Tab.
-- SELECT * FROM public.fn_get_hired_applicants('<vcode>');
-- Expected: row returned for the newly confirmed applicant.
--
-- V6: Confirm Hired count > 0 after approval.
-- SELECT COUNT(*) FROM public.fn_get_hired_applicants(NULL);
-- Expected: ≥ 1
--
-- V7: Confirm Pipeline count DECREMENTS after approval.
-- Pipeline = active_applicant_count in vw_vacancy_list
-- (status must NOT be in active set: New/For Interview/For
--  Requirements/For Onboard — 'Confirmed Onboard' is excluded
--  from the active set, so Pipeline correctly decrements.)
--
-- V8: Legacy applicant with hired_date only, hired_at = NULL.
-- SELECT id, status, hired_date, hired_at, hired_visible_until
-- FROM public.applicants
-- WHERE hired_date IS NOT NULL AND hired_at IS NULL
--   AND COALESCE(is_archived, false) = false
-- LIMIT 5;
-- Expected: hired_visible_until IS NOT NULL (set by §1 backfill)
--
-- V9: Window expiry — hired_visible_until < NOW() → NOT returned.
-- UPDATE public.applicants
-- SET hired_visible_until = NOW() - INTERVAL '1 second'
-- WHERE id = '<test_applicant_id>';
-- SELECT COUNT(*) FROM public.fn_get_hired_applicants(NULL)
-- WHERE id = '<test_applicant_id>';
-- Expected: 0 (correctly excluded after window expires)
-- ============================================================
