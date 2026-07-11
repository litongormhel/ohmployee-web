-- Migration: 20260527000000_unify_role_level_source.sql
-- Ticket: OHM2026_1044 — Fix Role Level Source-of-Truth Drift (G1 + G2)
--
-- Problem:
--   get_my_role_level() was a hardcoded CASE (role_name → int) and ignored
--   roles.role_level. get_target_role_level() already read the table, so actor
--   and target level comparisons in can_manage_target_user() used two different
--   sources — a silent divergence risk.
--
-- Fix:
--   1. Seed roles.role_level with the canonical levels that were previously
--      hardcoded in the CASE statement (authoritative enforcement values).
--   2. Rewrite get_my_role_level() to resolve the effective role name via
--      get_effective_role() (acting-session aware) then return roles.role_level.
--      Unknown role → 0 (no privilege escalation on fallback).
--
-- Invariants preserved:
--   - SECURITY DEFINER + SET search_path = 'public' maintained on all helpers
--   - is_super_admin()   = get_my_role_level() >= 100         (unchanged)
--   - i_have_full_access() = role_name IN (SA, HA)            (unchanged)
--   - can_manage_target_user() compares actor vs target level  (now both read table)
--   - Inactive / missing profile → get_effective_role() → 'Unknown' → level 0
--
-- No Flutter changes required.
-- No existing RLS policies or RPCs altered beyond get_my_role_level() itself.

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 1: Seed roles.role_level from the canonical CASE mapping.
--
-- These are the authoritative levels that have been live-enforced by the CASE
-- statement. The UPDATE is idempotent: re-running it is safe.
-- Roles not matched by role_name are left at their existing value.
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE public.roles
SET role_level = CASE role_name
  WHEN 'Super Admin'        THEN 100
  WHEN 'Head Admin'         THEN 90
  WHEN 'Operations Manager' THEN 70
  WHEN 'OM'                 THEN 70
  WHEN 'HRCO'               THEN 45
  WHEN 'ATL/TL'             THEN 40
  WHEN 'ATL'                THEN 42
  WHEN 'TL'                 THEN 41
  WHEN 'Encoder'            THEN 30
  WHEN 'HR Personnel'       THEN 25
  WHEN 'Recruitment Team'   THEN 20
  WHEN 'Recruitment'        THEN 20
  WHEN 'Back Office'        THEN 15
  WHEN 'Backoffice'         THEN 15
  WHEN 'Backoffice Personnel' THEN 15
  WHEN 'Viewer'             THEN 10
  ELSE role_level
END
WHERE role_name IN (
  'Super Admin', 'Head Admin',
  'Operations Manager', 'OM',
  'HRCO',
  'ATL/TL', 'ATL', 'TL',
  'Encoder',
  'HR Personnel',
  'Recruitment Team', 'Recruitment',
  'Back Office', 'Backoffice', 'Backoffice Personnel',
  'Viewer'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 2: Replace get_my_role_level() with a table-backed lookup.
--
-- Resolves the effective role name (acting-session aware via get_effective_role),
-- then returns roles.role_level for that name.
-- Fallback: 0 — unknown or inactive callers get no privileges.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_my_role_level()
  RETURNS integer
  LANGUAGE plpgsql
  STABLE SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_role text;
BEGIN
  v_role := public.get_effective_role();

  RETURN COALESCE(
    (SELECT r.role_level
     FROM public.roles r
     WHERE r.role_name = v_role
     LIMIT 1),
    0
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Validation notes (run against a staging/dev instance before prod deploy)
--
-- 1. Confirm roles table was seeded correctly:
--    SELECT role_name, role_level FROM public.roles ORDER BY role_level DESC;
--    Expected: SA=100, HA=90, OM=70, HRCO=45, ATL=42, TL=41, ATL/TL=40,
--              Encoder=30, HR Personnel=25, Recruitment=20, Backoffice=15, Viewer=10
--
-- 2. Verify get_my_role_level() returns the table value for the calling user:
--    SET LOCAL ROLE authenticated;
--    SELECT public.get_my_role_level(), public.get_my_role();
--    Expected: level matches roles.role_level for the returned role_name
--
-- 3. Verify can_manage_target_user() symmetry:
--    Actor and target both now derive level from roles.role_level (table).
--    get_target_role_level() already read the table before this migration.
--    No logic change needed there.
--
-- 4. Verify fallback safety:
--    A user with a role_name not in roles returns level 0 from
--    get_my_role_level(). No privilege escalation is possible.
--
-- 5. No Flutter changes required:
--    Flutter reads roles.role_level via the Supabase client (LoggedInUser.roleLevel).
--    After Step 1, the table values match what the CASE was returning, so
--    client-side level comparisons remain behaviorally equivalent.
-- ─────────────────────────────────────────────────────────────────────────────
