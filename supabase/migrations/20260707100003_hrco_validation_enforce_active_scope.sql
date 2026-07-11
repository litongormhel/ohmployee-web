-- Migration: 20260707100003_hrco_validation_enforce_active_scope
-- Created: 2026-07-07
-- Prompt: ohm#p7d4z9lx (HRCO Validation Hardening — Enforce Active Scope Only, W4 Fix)
-- Post-audit finding: ohm#v3m8c2ra W4 — fn_is_valid_hrco_for_account did not check
--   user_scopes.is_active, allowing revoked HRCO users to still pass validation.
--
-- Change: Add AND us.is_active = true to the user_scopes subquery inside
--   fn_is_valid_hrco_for_account. Single-line surgical addition — no logic, structure,
--   or grant changes of any kind. No RLS, no table, no index changes.
--
-- Safety note: user_scopes.is_active existence was flagged (W4) as requiring schema
--   verification before PROD apply. This migration adds a column-existence guard:
--   if the column does not exist on the target environment, the migration raises a
--   clear error rather than silently doing nothing or corrupting the function.
--
-- Scope: fn_is_valid_hrco_for_account ONLY. No other function touched.
--   assign_hrco_to_plantilla, search_account_hrcos, import RPCs — all unchanged.
--
-- Regression surface: Assign/Reassign RPC, CSV import HRCO_EMAIL path, RLS on
--   plantilla — none of these are modified. The function signature (p_user_id uuid,
--   p_account_id uuid) → boolean is unchanged.
--
-- Verification queries (run after apply, capture output):
--   V1 (active HRCO)        — should return TRUE
--   V2 (inactive scope)     — should return FALSE
--   V3 (non-HRCO user)      — should return FALSE
--   V4 (cross-account HRCO) — should return FALSE
--   (See below for query templates)

BEGIN;

-- ── Pre-flight: assert user_scopes.is_active exists ──────────────────────────
-- Fail loudly if the column is absent (W4 schema verification gate).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'user_scopes'
       AND column_name  = 'is_active'
  ) THEN
    RAISE EXCEPTION
      'MIGRATION ABORTED: public.user_scopes.is_active column does not exist. '
      'Verify the schema on this environment before applying this migration. '
      'Add the column (boolean NOT NULL DEFAULT true) if intentionally missing.';
  END IF;
END;
$$;

-- ── Hardened validation function ──────────────────────────────────────────────
-- Adds AND us.is_active = true to the user_scopes sub-SELECT.
-- All other logic is byte-for-byte identical to the previous version.
CREATE OR REPLACE FUNCTION public.fn_is_valid_hrco_for_account(p_user_id uuid, p_account_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE up.auth_user_id = p_user_id
      AND COALESCE(up.is_active, true)
      AND r.role_name = 'HRCO'
      AND EXISTS (
        SELECT 1 FROM public.user_scopes us
        WHERE us.user_id = up.id
          AND us.is_active = true          -- W4 fix: only active scopes are valid
          AND (
            us.account_id = p_account_id
            OR us.group_id = (SELECT group_id FROM public.accounts WHERE id = p_account_id)
          )
      )
  );
$$;

-- ── Verification query templates (execute manually after apply) ───────────────
-- Replace the UUIDs with real values from your staging/prod environment.
--
-- V1 — Active HRCO on the account → expect TRUE
-- SELECT public.fn_is_valid_hrco_for_account(
--   '<auth_uid_of_active_hrco>',
--   '<account_id>'
-- );
--
-- V2 — HRCO whose user_scope row has is_active = false → expect FALSE
-- -- Setup (transactional — roll back after):
-- BEGIN;
--   UPDATE public.user_scopes SET is_active = false
--    WHERE user_id = (SELECT id FROM public.users_profile WHERE auth_user_id = '<hrco_auth_uid>')
--      AND (account_id = '<account_id>' OR group_id = (SELECT group_id FROM public.accounts WHERE id = '<account_id>'));
--   SELECT public.fn_is_valid_hrco_for_account('<hrco_auth_uid>', '<account_id>');
--   -- Must return FALSE
-- ROLLBACK;
--
-- V3 — Non-HRCO user (any Encoder/OM/TL profile) → expect FALSE
-- SELECT public.fn_is_valid_hrco_for_account(
--   '<auth_uid_of_non_hrco_user>',
--   '<account_id>'
-- );
--
-- V4 — HRCO scoped to a DIFFERENT account → expect FALSE
-- SELECT public.fn_is_valid_hrco_for_account(
--   '<auth_uid_of_hrco_on_other_account>',
--   '<account_id>'
-- );

COMMIT;
