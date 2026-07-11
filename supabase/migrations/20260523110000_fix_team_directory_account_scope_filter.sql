-- ============================================================
-- OHM2026_2070 — Fix Role Summary Visibility After Role Change
-- ============================================================
-- Root cause:
--   upsert_user_profile_and_scopes replaces user_scopes with
--   group-level-only rows (user_id + group_id, account_id = NULL).
--   get_team_directory p_account_id filter required an exact
--   user_scopes.account_id match — so users updated via User
--   Management had no account_id scope and were invisible in the
--   Plantilla role summary even after a valid role change.
--
-- Fix:
--   Extend the p_account_id filter to also match users whose
--   group-level scope resolves to the target account's group
--   (via accounts.group_id NOT NULL).  Users with either a
--   direct account_id scope OR a group scope that covers the
--   account will now appear in the role summary.
--
-- No schema changes — DROP/CREATE function only.
-- Safe to apply after 20260523100000_fix_user_management_backend.
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
DECLARE
  v_caller_uid        UUID := auth.uid();
  v_caller_profile_id UUID;
  v_caller_role_level INT;
  v_caller_group_ids  UUID[];
BEGIN
  -- ── 1. Authentication guard ───────────────────────────────────────────────
  IF v_caller_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: team directory requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  -- ── 2. Resolve caller profile and role level ──────────────────────────────
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

  -- ── 3. Viewer / below: no directory access ────────────────────────────────
  IF COALESCE(v_caller_role_level, 0) <= 10 THEN
    RETURN;
  END IF;

  -- ── 4. Resolve caller group scope for scoped-access roles ─────────────────
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
    NULL::TEXT                                     AS profile_photo_url,
    up.full_name_search

  FROM  public.users_profile up
  JOIN  public.roles r ON r.id = up.role_id

  WHERE
    up.is_active   = TRUE
    AND r.role_level > 10

    AND CASE
          WHEN v_caller_role_level = 100 THEN TRUE
          WHEN v_caller_role_level = 90  THEN TRUE
          WHEN v_caller_role_level = 20  THEN r.role_level < 100
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
          WHEN v_caller_role_level BETWEEN 15 AND 45
           AND v_caller_role_level <> 20 THEN
            v_caller_group_ids IS NOT NULL
            AND EXISTS (
              SELECT 1
              FROM   public.user_scopes us_t
              WHERE  us_t.user_id  = up.id
                AND  us_t.group_id = ANY(v_caller_group_ids)
            )
          ELSE FALSE
        END

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
    -- ── FIX (OHM2026_2070): accept group-level scopes for account lookup ─────
    -- upsert_user_profile_and_scopes stores group-level scopes only
    -- (user_id + group_id; no account_id rows are written).  A user
    -- assigned to a group is implicitly scoped to all accounts in that
    -- group.  The OR branch resolves the account's group_id and matches
    -- users whose group scope covers it, so role-changed users remain
    -- visible in the Plantilla account role summary.
    AND (
      p_account_id IS NULL
      -- Direct account-level scope (legacy / manually set rows)
      OR EXISTS (
        SELECT 1
        FROM   public.user_scopes us_f
        WHERE  us_f.user_id    = up.id
          AND  us_f.account_id = p_account_id
      )
      -- Group-level scope that covers the account's group
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
