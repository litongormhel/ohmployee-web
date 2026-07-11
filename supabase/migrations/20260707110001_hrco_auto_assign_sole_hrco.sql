-- Migration: 20260707110001_hrco_auto_assign_sole_hrco
-- Created: 2026-07-07
-- Prompt: ohm#7f3k2a91 (Fix HRCO Assignment Leakage + Plantilla Active Filtering)
-- Purpose: Implement the Default HRCO Assignment rule -- if exactly one HRCO
--   exists on an account's roster, every new ACTIVE plantilla employee for that
--   account is auto-assigned to that HRCO at creation time. Existing assignments
--   are never touched, and nothing happens once a second HRCO is added to the
--   roster (no redistribution).
--
-- Design: a single AFTER INSERT ROW trigger on public.plantilla, not per-RPC
--   wiring. Every plantilla-creation path (move_to_plantilla, CSV baseline
--   import approval, coverage onboarding, additional-store) inserts into
--   public.plantilla directly, so one trigger covers "employee creation" and
--   "plantilla sync" from the ADR without touching any of those RPC bodies.
--   INSERT-only by design: existing rows are never re-evaluated, so adding a
--   second HRCO later cannot redistribute already-assigned employees.
--
-- Safety: the trigger body is wrapped in its own exception handler so a failure
--   in the auto-assign logic can never block the underlying plantilla INSERT
--   (belt-and-suspenders, same pattern already used by trg_coverage_request_notify).
--
-- Smoke Tests (run after apply, capture real output before COMPLETE):
-- S1: BEGIN; -- pick an account with exactly one HRCO on its roster and zero
--     plantilla_hrco_assignments rows for that account.
--     INSERT a new plantilla row with status='Active' for that account.
--     SELECT * FROM plantilla_hrco_assignments WHERE plantilla_id = <new id>;
--     -- expect: exactly one row, assignment_source = 'auto_single_hrco',
--     -- hrco_user_id = the account's sole HRCO. ROLLBACK;
-- S2: Repeat S1 for an account with 0 or 2+ HRCOs on its roster -- expect no
--     plantilla_hrco_assignments row created.
-- S3: For an account with exactly one HRCO, insert two new plantilla rows, then
--     add a second HRCO to the account roster, then insert a third plantilla row.
--     Confirm the first two rows keep their auto-assignment untouched and the
--     third row does NOT get auto-assigned (roster no longer has exactly one HRCO).

BEGIN;

ALTER TABLE public.plantilla_hrco_assignments
  DROP CONSTRAINT IF EXISTS plantilla_hrco_assignments_assignment_source_check;

ALTER TABLE public.plantilla_hrco_assignments
  ADD CONSTRAINT plantilla_hrco_assignments_assignment_source_check
  CHECK (assignment_source IN ('manual', 'csv_import', 'auto_single_hrco'));

-- ── Core logic: auto-assign if exactly one HRCO exists on this account's roster ──
CREATE OR REPLACE FUNCTION public.fn_maybe_auto_assign_sole_hrco(p_plantilla_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_account_id  uuid;
  v_employee_no text;
  v_status      text;
  v_hrco_count  int;
  v_sole_hrco   uuid;
  v_assigned_by uuid;
BEGIN
  SELECT account_id, employee_no, status INTO v_account_id, v_employee_no, v_status
    FROM public.plantilla WHERE id = p_plantilla_id;

  IF v_account_id IS NULL OR v_status IS DISTINCT FROM 'Active' THEN
    RETURN;
  END IF;

  -- Already assigned (e.g. HRCO_EMAIL CSV import ran in the same transaction) -- no-op.
  IF EXISTS (
    SELECT 1 FROM public.plantilla_hrco_assignments
     WHERE plantilla_id = p_plantilla_id AND is_active
  ) THEN
    RETURN;
  END IF;

  SELECT count(DISTINCT up.auth_user_id) INTO v_hrco_count
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE r.role_name = 'HRCO'
     AND COALESCE(up.is_active, true)
     AND EXISTS (
       SELECT 1 FROM public.user_scopes us
        WHERE us.user_id = up.id
          AND COALESCE(us.is_active, true)
          AND (
            us.account_id = v_account_id
            OR us.group_id = (SELECT group_id FROM public.accounts WHERE id = v_account_id)
          )
     );

  IF v_hrco_count <> 1 THEN
    RETURN;
  END IF;

  SELECT DISTINCT up.auth_user_id INTO v_sole_hrco
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE r.role_name = 'HRCO'
     AND COALESCE(up.is_active, true)
     AND EXISTS (
       SELECT 1 FROM public.user_scopes us
        WHERE us.user_id = up.id
          AND COALESCE(us.is_active, true)
          AND (
            us.account_id = v_account_id
            OR us.group_id = (SELECT group_id FROM public.accounts WHERE id = v_account_id)
          )
     )
   LIMIT 1;

  -- assigned_by is NOT NULL -- prefer the acting caller's profile id, fall back
  -- to the HRCO's own profile id so this never raises inside the trigger.
  v_assigned_by := COALESCE(
    public.get_current_profile_id(),
    (SELECT id FROM public.users_profile WHERE auth_user_id = v_sole_hrco)
  );

  INSERT INTO public.plantilla_hrco_assignments (
    plantilla_id, employee_no, account_id, hrco_user_id,
    hrco_email_snapshot, hrco_name_snapshot,
    assigned_by, assignment_source
  )
  SELECT p_plantilla_id, v_employee_no, v_account_id, v_sole_hrco,
         up.email, up.full_name,
         v_assigned_by, 'auto_single_hrco'
    FROM public.users_profile up
   WHERE up.auth_user_id = v_sole_hrco;
END;
$$;

-- Defense in depth: this is a system-side helper invoked only via the trigger
-- below (SECURITY DEFINER, bypasses RLS by design for the INSERT it performs).
-- It is idempotent and safe even if called directly (no-op unless status=Active,
-- unassigned, and exactly one HRCO on the roster), but there is no reason for
-- any client role to call it directly, so EXECUTE is revoked from client roles.
REVOKE EXECUTE ON FUNCTION public.fn_maybe_auto_assign_sole_hrco(uuid) FROM PUBLIC, authenticated, anon;

-- ── Trigger wrapper: never let auto-assign failure block the plantilla INSERT ──
CREATE OR REPLACE FUNCTION public.trg_auto_assign_sole_hrco()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
BEGIN
  BEGIN
    PERFORM public.fn_maybe_auto_assign_sole_hrco(NEW.id);
  EXCEPTION WHEN OTHERS THEN
    -- Never block the plantilla insert on an auto-assign failure, but surface
    -- it in the Postgres log (not a silent, permanently invisible failure).
    RAISE WARNING 'trg_auto_assign_sole_hrco: auto-assign failed for plantilla_id % - %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.trg_auto_assign_sole_hrco() FROM PUBLIC, authenticated, anon;

DROP TRIGGER IF EXISTS trg_plantilla_auto_assign_sole_hrco ON public.plantilla;
CREATE TRIGGER trg_plantilla_auto_assign_sole_hrco
  AFTER INSERT ON public.plantilla
  FOR EACH ROW EXECUTE FUNCTION public.trg_auto_assign_sole_hrco();

COMMIT;
