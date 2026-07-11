-- ============================================================
-- OHM2026_0071 — Team Directory UAT Fix Pack
-- ============================================================
-- Fix 1: Allow Viewer (role_level = 10) to access Team Directory.
--        Viewer callers see scoped-group contacts only (same rules
--        as Back Office and other level-15-to-45 scoped roles).
--        Viewer users still do not appear IN the directory
--        (base exclusion r.role_level > 10 is unchanged).
--
-- Fix 2: display_name format → "Last, First M." (single middle
--        initial + period; INITCAP proper case on last/first).
--        Omits initial when middle_name is NULL or empty.
--
-- Fix 3: p_search now searches name (full_name_search),
--        mobile_number, and email in addition to the existing
--        full_name_search column.
--
-- No schema changes — DROP/CREATE function only.
-- Safe to apply after: 20260523110000
-- ============================================================

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

  -- ── 3. Sub-Viewer guard — roles below level 10 get no access ─────────────
  -- Fix 1: threshold changed from <= 10 to < 10 so Viewer (level 10)
  -- passes through.  Any future sub-Viewer role (< 10) is still blocked.
  IF COALESCE(v_caller_role_level, 0) < 10 THEN
    RETURN;  -- empty result set, no error
  END IF;

  -- ── 4. Resolve caller's group scope for scoped-access roles ─────────────
  -- Applies to all callers below Head Admin (level < 90), including Viewer.
  IF COALESCE(v_caller_role_level, 0) < 90 THEN
    SELECT ARRAY_AGG(DISTINCT us.group_id)
    INTO   v_caller_group_ids
    FROM   public.user_scopes us
    WHERE  us.user_id   = v_caller_profile_id
      AND  us.group_id IS NOT NULL;

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

    -- Fix 2: display_name → "Last, First M." (INITCAP proper case;
    -- single middle initial + period; omitted when middle_name is absent).
    CASE
      WHEN up.last_name  IS NOT NULL
       AND up.first_name IS NOT NULL
        THEN TRIM(
               INITCAP(up.last_name) || ', ' || INITCAP(up.first_name)
               || CASE
                    WHEN up.middle_name IS NOT NULL
                     AND TRIM(up.middle_name) <> ''
                      THEN ' ' || UPPER(LEFT(TRIM(up.middle_name), 1)) || '.'
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
    AND r.role_level > 10         -- Viewer and below never appear in the directory

    -- ── RBAC + scope visibility gate (§2a) ───────────────────────────────────
    AND CASE
          -- Super Admin: sees all active directory users
          WHEN v_caller_role_level = 100 THEN
            TRUE

          -- Head Admin: sees all active directory users
          WHEN v_caller_role_level = 90 THEN
            TRUE

          -- Recruitment Team (20): all active users except Viewer (already
          -- filtered above) and Super Admin.
          WHEN v_caller_role_level = 20 THEN
            r.role_level < 100

          -- OM (70): peer OM visibility + lower-role users in own group scope.
          WHEN v_caller_role_level = 70 THEN
            r.role_level = 70
            OR (
              r.role_level < 70
              AND v_caller_group_ids IS NOT NULL
              AND EXISTS (
                SELECT 1
                FROM   public.user_scopes us_t
                WHERE  us_t.user_id  = up.id
                  AND  us_t.group_id = ANY(v_caller_group_ids)
              )
            )

          -- Fix 1: Viewer (10) added to the scoped-access band.
          -- Scoped-access roles: Viewer(10), Back Office(15), HR Personnel(25),
          -- Encoder(30), ATL/TL(40-42), HRCO(45).
          -- These see only users who share at least one group scope.
          -- Recruitment (20) is handled above with broader access.
          WHEN v_caller_role_level BETWEEN 10 AND 45
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

    -- ── Fix 3: p_search matches name, mobile number, or email ────────────────
    AND (
      p_search IS NULL
      OR up.full_name_search ILIKE '%' || LOWER(TRIM(p_search)) || '%'
      OR up.mobile_number    ILIKE '%' || TRIM(p_search)        || '%'
      OR LOWER(COALESCE(up.email, '')) ILIKE '%' || LOWER(TRIM(p_search)) || '%'
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
    -- OHM2026_2070 fix preserved: accept group-level scopes for account lookup.
    AND (
      p_account_id IS NULL
      OR EXISTS (
        SELECT 1
        FROM   public.user_scopes us_f
        WHERE  us_f.user_id    = up.id
          AND  us_f.account_id = p_account_id
      )
      OR EXISTS (
        SELECT 1
        FROM   public.user_scopes us_f
        JOIN   public.accounts    a  ON a.id = p_account_id
        WHERE  us_f.user_id  = up.id
          AND  us_f.group_id = a.group_id
      )
    )

  ORDER BY
    r.role_level DESC,
    up.last_name  ASC  NULLS LAST,
    up.first_name ASC  NULLS LAST;

END;
$$;

-- Access control unchanged — authenticated only.
REVOKE ALL     ON FUNCTION public.get_team_directory(TEXT, TEXT, UUID, UUID) FROM PUBLIC;
REVOKE ALL     ON FUNCTION public.get_team_directory(TEXT, TEXT, UUID, UUID) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_team_directory(TEXT, TEXT, UUID, UUID) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- VALIDATION QUERIES
-- ─────────────────────────────────────────────────────────────
/*
-- Fix 1: Viewer caller gets scoped results, not empty set
-- (execute as a Viewer user with at least one group scope)
SELECT COUNT(*) FROM public.get_team_directory();
-- Expected: > 0 rows from the caller's group scope

-- Fix 1: Sub-viewer (role_level < 10) still blocked
-- (no role currently uses levels below 10, future-proofed)

-- Fix 2: display_name uses single middle initial + proper case
SELECT last_name, first_name, middle_name, display_name
FROM   public.get_team_directory()
WHERE  middle_name IS NOT NULL
LIMIT  10;
-- Expected: "De La Cruz, Juan P." pattern (not "De la cruz, juan Pepito")

-- Fix 2: display_name omits initial when middle_name is NULL
SELECT last_name, first_name, middle_name, display_name
FROM   public.get_team_directory()
WHERE  middle_name IS NULL AND first_name IS NOT NULL
LIMIT  10;
-- Expected: "Reyes, Maria" (no trailing space or dot)

-- Fix 3: Search by mobile number
SELECT display_name, mobile_number
FROM   public.get_team_directory(p_search := '09171234567');
-- Expected: row whose mobile_number contains the search term

-- Fix 3: Search by email
SELECT display_name, email
FROM   public.get_team_directory(p_search := 'juan@example.com');
-- Expected: row whose email contains the search term

-- Fix 3: Search by name still works
SELECT display_name
FROM   public.get_team_directory(p_search := 'dela cruz');
-- Expected: rows where full_name_search contains 'dela cruz'
*/
