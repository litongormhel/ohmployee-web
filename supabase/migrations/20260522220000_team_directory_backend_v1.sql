-- ============================================================
-- OHM2026_2014 — Team Directory Backend Foundation V1
-- ============================================================
-- Creates get_team_directory() RPC — a safe, RBAC-enforced,
-- read-only operational contact directory for active OHMployee
-- users. Role-scoped visibility rules are applied server-side.
-- No sensitive HR data is exposed.
--
-- Depends on: 20260522200000_account_request_identity_v1_1.sql
--   (requires users_profile.last_name, first_name, middle_name,
--    mobile_number, full_name_search, directory_status columns)
--
-- Safe to apply after: 20260522210000
-- Does NOT modify existing RPCs, RLS policies, or table schemas
-- beyond the CHECK CONSTRAINT guard on directory_status.
-- Existing Request Account and approval flows are untouched.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- §1  Guard: directory_status CHECK CONSTRAINT
-- ─────────────────────────────────────────────────────────────
-- directory_status was added by 20260522200000 with:
--   TEXT NOT NULL DEFAULT 'Available'
-- This guard ensures only canonical V1 values are ever stored.
-- NOT VALID avoids a table scan (safe — existing rows are all 'Available').
-- Allowed V1 values: Available | Busy | On Leave | Offline

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM   pg_constraint
    WHERE  conname    = 'chk_users_profile_directory_status'
      AND  conrelid   = 'public.users_profile'::regclass
  ) THEN
    ALTER TABLE public.users_profile
      ADD CONSTRAINT chk_users_profile_directory_status
      CHECK (directory_status IN ('Available', 'Busy', 'On Leave', 'Offline'))
      NOT VALID;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- §2  RPC: get_team_directory
-- ─────────────────────────────────────────────────────────────
-- Team Directory is operational-contact only.
-- Purpose: allow OHMployee staff to find colleagues' names,
-- mobile numbers, and emails for work coordination.
--
-- Sensitive HR data MUST NOT be exposed via this function.
-- Visibility is RBAC + scope-based. See §2a for rules.
--
-- VISIBILITY RULES (§2a):
--
--   Super Admin  (100) : all active users in directory
--   Head Admin   (90)  : all active users in directory
--   OM           (70)  : all OMs + lower-role users in own group scope
--   Encoder      (30)  : users within own group scope only
--   Recruitment  (20)  : all active users except Viewer + Super Admin
--   HRCO         (45)  : users within own group scope only
--   ATL/TL     (40-42) : users within own group scope only
--   HR Personnel (25)  : users within own group scope only
--   Back Office  (15)  : users within own group scope only
--   Viewer       (10)  : directory access disabled — returns empty set
--
-- ALWAYS EXCLUDED:
--   is_active = false
--   role_level <= 10  (Viewer, Executive Viewer, any future sub-Viewer role)
--
-- SENSITIVE FIELDS NEVER EXPOSED:
--   Government IDs, salary, benefits, ATM/bank details,
--   personal HR records, approval notes, rejection notes,
--   private audit fields, deactivation notes.
--
-- NOTE: profile_photo_url returns NULL in V1.
--       A future migration will add a storage column to users_profile.

CREATE OR REPLACE FUNCTION public.get_team_directory(
  p_search     TEXT  DEFAULT NULL,
  p_role       TEXT  DEFAULT NULL,
  p_group_id   UUID  DEFAULT NULL,
  p_account_id UUID  DEFAULT NULL
)
RETURNS TABLE (
  auth_user_id      UUID,
  full_name         TEXT,
  last_name         TEXT,
  first_name        TEXT,
  middle_name       TEXT,
  display_name      TEXT,
  mobile_number     TEXT,
  email             TEXT,
  role_name         TEXT,
  role_level        INT,
  group_names       TEXT[],
  account_names     TEXT[],
  directory_status  TEXT,
  profile_photo_url TEXT,
  full_name_search  TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
-- ── Team Directory — operational contact access only ──────────────────────────
-- Sensitive HR data must not be exposed. Visibility is RBAC + scope-based.
DECLARE
  v_caller_uid        UUID := auth.uid();
  v_caller_profile_id UUID;
  v_caller_role_level INT;
  v_caller_group_ids  UUID[];
BEGIN
  -- ── 1. Authentication guard — anon may not call ───────────────────────────
  IF v_caller_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: team directory requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  -- ── 2. Resolve caller profile and effective role level ───────────────────
  SELECT up.id, r.role_level
  INTO   v_caller_profile_id, v_caller_role_level
  FROM   public.users_profile up
  JOIN   public.roles r ON r.id = up.role_id
  WHERE  up.auth_user_id = v_caller_uid
    AND  up.is_active = TRUE;

  IF v_caller_profile_id IS NULL THEN
    RAISE EXCEPTION 'team directory: caller profile not found or inactive'
      USING ERRCODE = '42501';
  END IF;

  -- ── 3. Viewer / below: no directory access ───────────────────────────────
  -- Viewer (level 10) and any future sub-Viewer roles are blocked here.
  -- This is intentional: Viewer should not appear in, or access, the directory.
  IF COALESCE(v_caller_role_level, 0) <= 10 THEN
    RETURN;  -- empty result set, no error
  END IF;

  -- ── 4. Resolve caller's group scope for scoped-access roles ─────────────
  -- Only needed for callers below Head Admin (level < 90).
  -- Scoped roles: OM(70), HRCO(45), ATL(42), TL(41), ATL/TL(40),
  --               Encoder(30), HR Personnel(25), Recruitment(20),
  --               Back Office(15).
  IF COALESCE(v_caller_role_level, 0) < 90 THEN
    -- Primary: read from user_scopes (canonical scope source)
    SELECT ARRAY_AGG(DISTINCT us.group_id)
    INTO   v_caller_group_ids
    FROM   public.user_scopes us
    WHERE  us.user_id   = v_caller_profile_id
      AND  us.group_id IS NOT NULL;

    -- Fallback: if user_scopes has no group rows, use users_profile.group_id
    IF v_caller_group_ids IS NULL THEN
      SELECT ARRAY[up.group_id]
      INTO   v_caller_group_ids
      FROM   public.users_profile up
      WHERE  up.id          = v_caller_profile_id
        AND  up.group_id IS NOT NULL;
    END IF;
  END IF;

  -- ── 5. Main directory query ───────────────────────────────────────────────
  RETURN QUERY
  SELECT
    up.auth_user_id,
    up.full_name,
    up.last_name,
    up.first_name,
    up.middle_name,

    -- display_name format: "Last Name, First Name Middle Name"
    -- Falls back to full_name for legacy rows without separated fields.
    CASE
      WHEN up.last_name  IS NOT NULL
       AND up.first_name IS NOT NULL
        THEN TRIM(
               up.last_name || ', ' || up.first_name
               || CASE
                    WHEN up.middle_name IS NOT NULL
                      THEN ' ' || up.middle_name
                    ELSE ''
                  END
             )
      ELSE up.full_name
    END::TEXT                                      AS display_name,

    up.mobile_number,
    up.email,
    r.role_name,
    r.role_level::INT                              AS role_level,

    -- group_names: aggregated from user_scopes; falls back to profile.group_id
    COALESCE(
      (
        SELECT ARRAY_AGG(DISTINCT g.group_name ORDER BY g.group_name)
        FROM   public.user_scopes us2
        JOIN   public.groups g ON g.id = us2.group_id
        WHERE  us2.user_id   = up.id
          AND  us2.group_id IS NOT NULL
      ),
      (
        SELECT ARRAY[g2.group_name]
        FROM   public.groups g2
        WHERE  g2.id = up.group_id
      ),
      ARRAY[]::TEXT[]
    )                                              AS group_names,

    -- account_names: aggregated from user_scopes
    COALESCE(
      (
        SELECT ARRAY_AGG(DISTINCT a.account_name ORDER BY a.account_name)
        FROM   public.user_scopes us3
        JOIN   public.accounts a ON a.id = us3.account_id
        WHERE  us3.user_id    = up.id
          AND  us3.account_id IS NOT NULL
      ),
      ARRAY[]::TEXT[]
    )                                              AS account_names,

    COALESCE(up.directory_status, 'Available')     AS directory_status,
    NULL::TEXT                                     AS profile_photo_url,  -- V1: reserved
    up.full_name_search

  FROM  public.users_profile up
  JOIN  public.roles r ON r.id = up.role_id

  WHERE
    -- ── Base exclusions (always applied) ─────────────────────────────────────
    up.is_active   = TRUE
    AND r.role_level > 10         -- exclude Viewer (10) and below from all views

    -- ── RBAC + scope visibility gate (§2a) ───────────────────────────────────
    AND CASE
          -- Super Admin: sees all active directory users
          WHEN v_caller_role_level = 100 THEN
            TRUE

          -- Head Admin: sees all active directory users
          WHEN v_caller_role_level = 90 THEN
            TRUE

          -- Recruitment Team (20): all active users except Viewer (already
          -- filtered above) and Super Admin (excluded for security —
          -- existing users_profile_read_scoped policy does not grant
          -- Recruitment access to role_level 100 rows).
          WHEN v_caller_role_level = 20 THEN
            r.role_level < 100

          -- OM (70): all OMs are mutually visible (peer visibility) PLUS
          -- lower-role users who share at least one group scope with the caller.
          WHEN v_caller_role_level = 70 THEN
            r.role_level = 70                    -- all OMs: unconditional
            OR (
              r.role_level < 70                  -- lower roles: scope required
              AND v_caller_group_ids IS NOT NULL
              AND EXISTS (
                SELECT 1
                FROM   public.user_scopes us_t
                WHERE  us_t.user_id  = up.id
                  AND  us_t.group_id = ANY(v_caller_group_ids)
              )
            )

          -- Scoped-access roles: Encoder(30), HR Personnel(25), HRCO(45),
          -- ATL(42), TL(41), ATL/TL(40), Back Office(15).
          -- These see only users who share at least one group scope.
          -- Recruitment (20) is handled above with broader access.
          WHEN v_caller_role_level BETWEEN 15 AND 45
           AND v_caller_role_level <> 20 THEN
            v_caller_group_ids IS NOT NULL
            AND EXISTS (
              SELECT 1
              FROM   public.user_scopes us_t
              WHERE  us_t.user_id  = up.id
                AND  us_t.group_id = ANY(v_caller_group_ids)
            )

          -- Fallback for any unlisted role: deny
          ELSE FALSE
        END

    -- ── Optional filters (all parameters default NULL = no filter) ────────────
    AND (
      p_search IS NULL
      OR up.full_name_search ILIKE '%' || LOWER(TRIM(p_search)) || '%'
    )
    AND (
      p_role IS NULL
      OR LOWER(r.role_name) = LOWER(p_role)
    )
    AND (
      p_group_id IS NULL
      OR EXISTS (
        SELECT 1
        FROM   public.user_scopes us_f
        WHERE  us_f.user_id  = up.id
          AND  us_f.group_id = p_group_id
      )
    )
    AND (
      p_account_id IS NULL
      OR EXISTS (
        SELECT 1
        FROM   public.user_scopes us_f
        WHERE  us_f.user_id    = up.id
          AND  us_f.account_id = p_account_id
      )
    )

  ORDER BY
    r.role_level DESC,                            -- higher roles first
    up.last_name  ASC  NULLS LAST,
    up.first_name ASC  NULLS LAST;

END;
$$;

-- ─────────────────────────────────────────────────────────────
-- §3  Access control
-- ─────────────────────────────────────────────────────────────
-- Revoke default PUBLIC (anon-inclusive) access.
-- Grant execute only to authenticated role.
-- The RPC itself enforces Viewer exclusion and all role gates.

REVOKE ALL    ON FUNCTION public.get_team_directory(TEXT, TEXT, UUID, UUID) FROM PUBLIC;
REVOKE ALL    ON FUNCTION public.get_team_directory(TEXT, TEXT, UUID, UUID) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_team_directory(TEXT, TEXT, UUID, UUID) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- VALIDATION QUERIES (read-only, execute manually to verify)
-- ─────────────────────────────────────────────────────────────
/*
-- V1: RPC is registered and SECURITY DEFINER
SELECT proname, prosecdef, provolatile
FROM   pg_proc
WHERE  proname = 'get_team_directory'
  AND  pronamespace = 'public'::regnamespace;
-- Expected: 1 row, prosecdef = true, provolatile = 's' (stable)

-- V2: Anon cannot call (execute as anon role)
SELECT * FROM public.get_team_directory();
-- Expected: ERROR 42501 "unauthenticated: team directory requires a valid session"

-- V3: Viewer gets empty result (execute as Viewer-role user)
SELECT COUNT(*) FROM public.get_team_directory();
-- Expected: 0 rows (no error, empty set)

-- V4: Super Admin sees all active non-Viewer users
-- (execute as Super Admin)
SELECT COUNT(*) FROM public.get_team_directory();
-- Expected: COUNT of all users_profile rows where is_active=true AND role_level > 10

-- V5: Head Admin sees all active non-Viewer users
-- (execute as Head Admin)
SELECT COUNT(*) FROM public.get_team_directory();
-- Expected: same as V4

-- V6: Recruitment Team does not see Super Admin or Viewer
-- (execute as Recruitment Team user)
SELECT role_name, COUNT(*) FROM public.get_team_directory()
GROUP BY role_name ORDER BY COUNT(*) DESC;
-- Expected: no 'Super Admin' row; no 'Viewer' row

-- V7: OM sees all OMs + only scoped lower roles
-- (execute as OM user with a known group scope)
SELECT role_name, COUNT(*) FROM public.get_team_directory()
GROUP BY role_name ORDER BY role_name;
-- Expected: all OM users present; other roles only if in caller's group scope

-- V8: Encoder sees only scoped users (execute as Encoder)
SELECT COUNT(*) FROM public.get_team_directory();
-- Expected: only users who share a group scope with the Encoder

-- V9: HRCO/ATL/TL see only scoped users (execute as HRCO)
SELECT COUNT(*) FROM public.get_team_directory();
-- Expected: only users in same group scope

-- V10: Search by name works
SELECT display_name, mobile_number
FROM   public.get_team_directory(p_search := 'dela cruz');
-- Expected: rows where full_name_search contains 'dela cruz'

-- V11: Role filter works
SELECT role_name, COUNT(*)
FROM   public.get_team_directory(p_role := 'Operations Manager')
GROUP BY role_name;
-- Expected: only 'Operations Manager' rows (subject to caller visibility)

-- V12: Group filter works
SELECT COUNT(*)
FROM   public.get_team_directory(p_group_id := '<some-group-uuid>');
-- Expected: only users in that group, subject to caller visibility

-- V13: Account filter works
SELECT COUNT(*)
FROM   public.get_team_directory(p_account_id := '<some-account-uuid>');
-- Expected: only users scoped to that account

-- V14: Sensitive fields not present in return schema
\d public.get_team_directory
-- Expected: no gov_id, salary, atm_number, bank_details, rejection_reason,
--           approval_notes, or other private HR columns in the return table

-- V15: directory_status constraint rejects invalid values
INSERT INTO public.users_profile (full_name, role_id, directory_status)
VALUES ('Test', '<any-role-id>', 'On Vacation');
-- Expected: ERROR violates check constraint chk_users_profile_directory_status

-- V16: directory_status constraint accepts all valid values
UPDATE public.users_profile SET directory_status = 'Busy'     WHERE id = '<test-id>';
UPDATE public.users_profile SET directory_status = 'On Leave'  WHERE id = '<test-id>';
UPDATE public.users_profile SET directory_status = 'Offline'   WHERE id = '<test-id>';
UPDATE public.users_profile SET directory_status = 'Available' WHERE id = '<test-id>';
-- Expected: all succeed with no error

-- V17: display_name format for a user with middle name
SELECT display_name FROM public.get_team_directory()
WHERE  first_name IS NOT NULL AND middle_name IS NOT NULL
LIMIT 5;
-- Expected: "De La Cruz, Juan Pepito" pattern (Last, First Middle)

-- V18: display_name format for a user without middle name
SELECT display_name FROM public.get_team_directory()
WHERE  first_name IS NOT NULL AND middle_name IS NULL
LIMIT 5;
-- Expected: "Reyes, Maria" pattern (Last, First — no trailing space)

-- V19: profile_photo_url is NULL in V1
SELECT profile_photo_url FROM public.get_team_directory() LIMIT 1;
-- Expected: NULL (reserved for future storage column)

-- V20: Existing Request Account flow unaffected
SELECT COUNT(*) FROM public.v_approval_queue WHERE status = 'pending';
-- Expected: same count as before migration — no approval workflow rows changed
*/
