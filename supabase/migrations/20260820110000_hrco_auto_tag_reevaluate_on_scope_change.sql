-- Migration: 20260820110000_hrco_auto_tag_reevaluate_on_scope_change
-- Created: 2026-08-20
-- Prompt: ohm#7k3wm9xq (HRCO Auto-Tag Not Firing on 0->1 HRCO Transition)
-- Purpose: Close the gap found in investigation ohm#7k3wm9xq -- the existing
--   single-HRCO auto-assign trigger (20260707110001/20260713133000) only fires
--   on public.plantilla INSERT or UPDATE OF status, so it never re-evaluates
--   already-existing Active employees when an account's HRCO roster itself
--   changes (0->1, 1->0, or 1->a-different-1). Repro: BANKO went 0 HRCO -> 1
--   HRCO (T. Mendoza added); its 10 pre-existing Active employees stayed
--   "Needs HRCO" because nothing re-evaluated them.
--
-- Design (per Ohm's approved fix plan):
--   Hook on public.user_scopes (AFTER INSERT OR UPDATE OR DELETE), not on
--   accounts.hrco_user_id -- user_scopes is the actual live source of truth
--   the existing HRCO-count query already reads (fn_maybe_auto_assign_sole_hrco),
--   and it's the one surface that catches every roster-change path: the
--   accounts.hrco_user_id field (via its own sync trigger from 20262606000034),
--   a direct scope grant, a role change, or a scope deactivation
--   (user_scopes.is_active flip -- no row insert/delete needed).
--
--   New function fn_reevaluate_hrco_auto_tags(p_account_id) reuses
--   fn_maybe_auto_assign_sole_hrco's HRCO-count query, then bulk-applies the
--   same per-row decision across every Active, non-deleted, non-archived
--   plantilla row in that account:
--     count = 0  -> deactivate assignment_source='auto_single_hrco' rows only
--                   (revert to "Needs HRCO"); manual/csv_import untouched.
--     count = 1  -> deactivate any active auto_single_hrco row pointing at a
--                   DIFFERENT hrco than the new sole HRCO (handles the
--                   1-HRCO-swapped-for-another-1-HRCO case), then auto-assign
--                   every currently-unassigned row to the sole HRCO.
--     count > 1  -> no-op (no redistribution on multi-HRCO rosters, matches
--                   the existing plantilla-level trigger's documented rule).
--   manual and csv_import assignment_source rows are never read/touched by
--   either branch -- only assignment_source='auto_single_hrco' rows are ever
--   deactivated, and the INSERT only ever fires for rows with zero active
--   assignment of ANY source.
--
--   trg_reevaluate_hrco_on_scope_change (on user_scopes) resolves the
--   affected account(s) from whichever of NEW/OLD applies for the op, but
--   only when the scope row belongs to an HRCO-role user (checked via
--   fn_user_is_hrco). An account-level row affects exactly that account; a
--   group-level row (account_id NULL) affects every account in that group,
--   since fn_maybe_auto_assign_sole_hrco's count query already treats
--   group-level HRCO scope as covering all accounts in the group. On UPDATE,
--   both the NEW scope and (if account_id/group_id actually changed) the OLD
--   scope are re-evaluated, so a moved assignment settles both the account
--   the HRCO left and the one they joined.
--
-- Explicitly NOT touched: the existing trg_plantilla_auto_assign_sole_hrco
-- trigger and fn_maybe_auto_assign_sole_hrco function on public.plantilla --
-- reused via the same query shape, not modified. Both mechanisms can now
-- run in the same transaction (e.g. a new Active plantilla row inserted the
-- same moment a scope changes) -- no conflict, since both are idempotent
-- (NOT EXISTS-gated inserts) and the second one to run is simply a no-op for
-- rows the first one already handled.
--
-- Safety: both new functions are wrapped the same way as the existing
-- pattern (trigger body exception-handled with RAISE WARNING, never blocks
-- the underlying user_scopes write). EXECUTE revoked from client roles --
-- system-side only, invoked via trigger.
--
-- Known residual gap (flagged, not fixed here, out of the approved scope):
-- deactivating a user via users_profile.is_active does NOT itself touch
-- user_scopes, so that path alone will not fire this trigger. If that gap
-- matters it needs a separate trigger on users_profile -- deferred pending
-- a decision, per the investigation's regression risk note.
--
-- Smoke Tests (run after apply, capture real output before COMPLETE):
-- S1 (0->1, the reported bug): BEGIN; pick an account with 0 HRCO scope rows
--     and >=1 Active "Needs HRCO" plantilla row. INSERT a user_scopes row
--     for an HRCO-role user at that account_id. SELECT plantilla_id,
--     hrco_user_id, assignment_source FROM plantilla_hrco_assignments WHERE
--     account_id = <account> AND is_active; -- expect one row per previously
--     unassigned Active employee, assignment_source='auto_single_hrco'.
--     ROLLBACK;
-- S2 (1->0): BEGIN; pick an account with exactly 1 HRCO and >=1
--     auto_single_hrco-assigned employee. DELETE (or is_active=false UPDATE)
--     that HRCO's user_scopes row. SELECT ... WHERE account_id=<account> AND
--     assignment_source='auto_single_hrco'; -- expect those rows now
--     is_active=false, effective_end set. ROLLBACK;
-- S3 (1 HRCO swapped for a different 1 HRCO): BEGIN; account with exactly 1
--     HRCO (X) and auto-assigned employees. DELETE X's scope row, INSERT a
--     new user_scopes row for a different HRCO-role user Y at the same
--     account. SELECT ...; -- expect the old X-pointing auto rows
--     is_active=false, new Y-pointing auto rows is_active=true for the same
--     employees. ROLLBACK;
-- S4 (manual/csv_import preserved): BEGIN; account going 0->1 per S1, but
--     one employee already has an active assignment_source='manual' row to
--     some other user. Fire the same 0->1 transition. Confirm that
--     employee's manual row is untouched (not deactivated, not duplicated).
--     ROLLBACK;
-- S5 (multi-HRCO no-op): BEGIN; account with 2 active HRCO scope rows,
--     unassigned employees. INSERT a 3rd HRCO scope row. Confirm zero new
--     plantilla_hrco_assignments rows were created. ROLLBACK;
-- S6 (group-level scope): BEGIN; account with 0 HRCO, unassigned employees,
--     whose accounts.group_id has zero other HRCO. INSERT a user_scopes row
--     for an HRCO-role user with group_id set (account_id NULL) matching
--     that account's group. Confirm the account's employees get
--     auto-assigned to that HRCO. ROLLBACK.

BEGIN;

-- ── Small helper: is this users_profile id an active HRCO? ──────────────────
CREATE OR REPLACE FUNCTION public.fn_user_is_hrco(p_profile_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE up.id = p_profile_id
      AND r.role_name = 'HRCO'
      AND COALESCE(up.is_active, true)
  );
$$;

REVOKE EXECUTE ON FUNCTION public.fn_user_is_hrco(uuid) FROM PUBLIC, authenticated, anon;

-- ── Core logic: bring one account's auto-tags in line with its live HRCO count ──
CREATE OR REPLACE FUNCTION public.fn_reevaluate_hrco_auto_tags(p_account_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_hrco_count  int;
  v_sole_hrco   uuid;
  v_assigned_by uuid;
BEGIN
  IF p_account_id IS NULL THEN
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
            us.account_id = p_account_id
            OR us.group_id = (SELECT group_id FROM public.accounts WHERE id = p_account_id)
          )
     );

  IF v_hrco_count = 0 THEN
    -- Revert to "Needs HRCO" -- auto-assigned rows only, never manual/csv_import.
    UPDATE public.plantilla_hrco_assignments
       SET is_active = false, effective_end = now()
     WHERE account_id = p_account_id
       AND is_active
       AND assignment_source = 'auto_single_hrco';
    RETURN;
  END IF;

  IF v_hrco_count > 1 THEN
    -- No redistribution on multi-HRCO rosters -- leave every existing
    -- assignment (auto, manual, csv_import) exactly as-is.
    RETURN;
  END IF;

  -- Exactly one HRCO on the roster.
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
            us.account_id = p_account_id
            OR us.group_id = (SELECT group_id FROM public.accounts WHERE id = p_account_id)
          )
     )
   LIMIT 1;

  v_assigned_by := COALESCE(
    public.get_current_profile_id(),
    (SELECT id FROM public.users_profile WHERE auth_user_id = v_sole_hrco)
  );

  -- Sole HRCO changed identity (e.g. account had HRCO X, now has HRCO Y) --
  -- deactivate stale auto rows pointing at the old HRCO. Manual/csv_import
  -- rows are excluded from this WHERE and are never touched.
  UPDATE public.plantilla_hrco_assignments pha
     SET is_active = false, effective_end = now()
   WHERE pha.account_id = p_account_id
     AND pha.is_active
     AND pha.assignment_source = 'auto_single_hrco'
     AND pha.hrco_user_id IS DISTINCT FROM v_sole_hrco;

  -- Auto-assign every Active, non-deleted, non-archived employee in this
  -- account that currently has zero active assignment of ANY source. This
  -- single INSERT covers both genuinely-never-assigned employees and the
  -- ones just freed up by the re-tag UPDATE above.
  INSERT INTO public.plantilla_hrco_assignments (
    plantilla_id, employee_no, account_id, hrco_user_id,
    hrco_email_snapshot, hrco_name_snapshot,
    assigned_by, assignment_source
  )
  SELECT p.id, p.employee_no, p.account_id, v_sole_hrco,
         up.email, up.full_name,
         v_assigned_by, 'auto_single_hrco'
    FROM public.plantilla p
    JOIN public.users_profile up ON up.auth_user_id = v_sole_hrco
   WHERE p.account_id = p_account_id
     AND p.status = 'Active'
     AND p.is_deleted IS NOT TRUE
     AND (p.is_archived = false OR p.is_archived IS NULL)
     AND NOT EXISTS (
       SELECT 1 FROM public.plantilla_hrco_assignments pha
        WHERE pha.plantilla_id = p.id AND pha.is_active
     );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_reevaluate_hrco_auto_tags(uuid) FROM PUBLIC, authenticated, anon;

-- ── Trigger wrapper on user_scopes: resolve affected account(s), never block the write ──
CREATE OR REPLACE FUNCTION public.trg_reevaluate_hrco_on_scope_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_acct record;
BEGIN
  BEGIN
    IF TG_OP = 'DELETE' THEN
      IF public.fn_user_is_hrco(OLD.user_id) THEN
        IF OLD.account_id IS NOT NULL THEN
          PERFORM public.fn_reevaluate_hrco_auto_tags(OLD.account_id);
        ELSIF OLD.group_id IS NOT NULL THEN
          FOR v_acct IN SELECT id FROM public.accounts WHERE group_id = OLD.group_id LOOP
            PERFORM public.fn_reevaluate_hrco_auto_tags(v_acct.id);
          END LOOP;
        END IF;
      END IF;
      RETURN OLD;
    END IF;

    -- INSERT or UPDATE: always re-evaluate the NEW scope (covers is_active
    -- flips too, since the count query re-reads live user_scopes state).
    IF public.fn_user_is_hrco(NEW.user_id) THEN
      IF NEW.account_id IS NOT NULL THEN
        PERFORM public.fn_reevaluate_hrco_auto_tags(NEW.account_id);
      ELSIF NEW.group_id IS NOT NULL THEN
        FOR v_acct IN SELECT id FROM public.accounts WHERE group_id = NEW.group_id LOOP
          PERFORM public.fn_reevaluate_hrco_auto_tags(v_acct.id);
        END LOOP;
      END IF;
    END IF;

    -- On UPDATE, also settle the account/group the row moved OUT of.
    IF TG_OP = 'UPDATE' AND public.fn_user_is_hrco(OLD.user_id) THEN
      IF OLD.account_id IS NOT NULL AND OLD.account_id IS DISTINCT FROM NEW.account_id THEN
        PERFORM public.fn_reevaluate_hrco_auto_tags(OLD.account_id);
      ELSIF OLD.group_id IS NOT NULL AND OLD.group_id IS DISTINCT FROM NEW.group_id THEN
        FOR v_acct IN SELECT id FROM public.accounts WHERE group_id = OLD.group_id LOOP
          PERFORM public.fn_reevaluate_hrco_auto_tags(v_acct.id);
        END LOOP;
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- COALESCE(NEW.id, OLD.id) would itself error on DELETE (field access on
    -- an unassigned NEW record raises before COALESCE can short-circuit) --
    -- branch on TG_OP explicitly so this handler can never fail the write
    -- it exists to protect.
    RAISE WARNING 'trg_reevaluate_hrco_on_scope_change: failed for user_scopes id % (op %) - %',
      CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END, TG_OP, SQLERRM;
  END;

  RETURN COALESCE(NEW, OLD);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.trg_reevaluate_hrco_on_scope_change() FROM PUBLIC, authenticated, anon;

DROP TRIGGER IF EXISTS trg_user_scopes_reevaluate_hrco ON public.user_scopes;
CREATE TRIGGER trg_user_scopes_reevaluate_hrco
  AFTER INSERT OR UPDATE OR DELETE ON public.user_scopes
  FOR EACH ROW EXECUTE FUNCTION public.trg_reevaluate_hrco_on_scope_change();

COMMIT;
