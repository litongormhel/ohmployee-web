-- ohm#j5r8n3wq — Fix (corrected, supersedes ohm#p6y3m8vd) — sync accounts.om_user_id /
-- atl_user_id / hrco_user_id into user_scopes, role-aware.
--
-- Bug: the account-assignment fields on `accounts` (om_user_id, atl_user_id, hrco_user_id)
-- were never synced into `user_scopes`, the sole table get_my_allowed_accounts() /
-- get_my_allowed_account_ids() read for RLS scope resolution.
--
-- Root design rule (load-bearing, do not change without re-deriving):
-- get_my_allowed_accounts() branches EXCLUSIVELY for every non-SA/HA role — "if this user
-- has ANY account-level user_scopes row, use ONLY account-level rows, ignore group fallback
-- entirely." OM must therefore NEVER receive an account-level row (only group-level), or the
-- next account assignment would silently revoke their group-fallback access to every other
-- account in their group. ATL/HRCO are correctly account-scoped, so they receive account-level
-- rows. TL/Encoder are out of scope — accounts has no tl_user_id/encoder_user_id column.
--
-- Additive-only: no revocation on reassignment (no way to distinguish assignment-derived scope
-- from manually-granted scope). Idempotent: ON CONFLICT DO NOTHING against the existing unique
-- constraint (user_id, group_id, account_id).
--
-- Known data-quality exception: ACTISERVE's hrco_user_id currently points to a user whose real
-- role is Back Office, not HRCO — excluded from this backfill by explicit account id so scope
-- isn't granted to mask a wrong-person assignment. The trigger does NOT special-case ACTISERVE
-- going forward — if hrco_user_id is later corrected there, the trigger will grant scope to the
-- right person then.

-- 1. Backfill: om_user_id -> group-level user_scopes row only.
INSERT INTO public.user_scopes (user_id, group_id, account_id)
SELECT DISTINCT a.om_user_id, a.group_id, NULL::uuid
FROM public.accounts a
WHERE a.om_user_id IS NOT NULL
ON CONFLICT (user_id, group_id, account_id) DO NOTHING;

-- 2. Backfill: atl_user_id -> account-level user_scopes row.
INSERT INTO public.user_scopes (user_id, account_id, group_id)
SELECT DISTINCT a.atl_user_id, a.id, NULL::uuid
FROM public.accounts a
WHERE a.atl_user_id IS NOT NULL
ON CONFLICT (user_id, group_id, account_id) DO NOTHING;

-- 3. Backfill: hrco_user_id -> account-level user_scopes row, excluding ACTISERVE
-- (confirmed wrong-role assignment, flagged for manual cleanup, not synced here).
INSERT INTO public.user_scopes (user_id, account_id, group_id)
SELECT DISTINCT a.hrco_user_id, a.id, NULL::uuid
FROM public.accounts a
WHERE a.hrco_user_id IS NOT NULL
  AND a.account_name <> 'ACTISERVE'
ON CONFLICT (user_id, group_id, account_id) DO NOTHING;

-- 4. Trigger: keep user_scopes in sync going forward on every future assignment change.
CREATE OR REPLACE FUNCTION public.fn_sync_account_assignments_to_user_scopes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.om_user_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.om_user_id IS DISTINCT FROM OLD.om_user_id) THEN
    INSERT INTO public.user_scopes (user_id, group_id, account_id)
    VALUES (NEW.om_user_id, NEW.group_id, NULL)
    ON CONFLICT (user_id, group_id, account_id) DO NOTHING;
  END IF;

  IF NEW.atl_user_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.atl_user_id IS DISTINCT FROM OLD.atl_user_id) THEN
    INSERT INTO public.user_scopes (user_id, account_id, group_id)
    VALUES (NEW.atl_user_id, NEW.id, NULL)
    ON CONFLICT (user_id, group_id, account_id) DO NOTHING;
  END IF;

  IF NEW.hrco_user_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.hrco_user_id IS DISTINCT FROM OLD.hrco_user_id) THEN
    INSERT INTO public.user_scopes (user_id, account_id, group_id)
    VALUES (NEW.hrco_user_id, NEW.id, NULL)
    ON CONFLICT (user_id, group_id, account_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_sync_account_assignments_to_user_scopes ON public.accounts;

CREATE TRIGGER trg_sync_account_assignments_to_user_scopes
AFTER INSERT OR UPDATE OF om_user_id, atl_user_id, hrco_user_id ON public.accounts
FOR EACH ROW
EXECUTE FUNCTION public.fn_sync_account_assignments_to_user_scopes();
