-- Global Search Index RPC
-- Ticket: OHM2026_6969
-- Phase 1: Backend global search across Vacancy, HR Emploc, Plantilla, Applicants
-- Access: Data Team only (superAdmin, headAdmin, encoder)
-- Security: SECURITY DEFINER with auth.uid() caller check + scope enforcement

-- ── Performance indexes (idempotent) ──────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_vacancies_vcode_upper
  ON vacancies (upper(vcode));

CREATE INDEX IF NOT EXISTS idx_vacancies_account
  ON vacancies (account);

CREATE INDEX IF NOT EXISTS idx_hr_emploc_emploc_no_upper
  ON hr_emploc (upper(emploc_no));

CREATE INDEX IF NOT EXISTS idx_hr_emploc_account
  ON hr_emploc (account);

CREATE INDEX IF NOT EXISTS idx_plantilla_employee_name_trgm
  ON plantilla USING gin (upper(employee_name) gin_trgm_ops)
  WHERE employee_name IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_plantilla_account
  ON plantilla (account);

CREATE INDEX IF NOT EXISTS idx_applicants_name_trgm
  ON applicants USING gin (
    upper(coalesce(first_name,'') || ' ' || coalesce(last_name,'')) gin_trgm_ops
  );

-- ── Helper: normalize a role_name string for comparison ───────────────────────

CREATE OR REPLACE FUNCTION _ohm_normalize_role(p_role text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(regexp_replace(coalesce(p_role, ''), '[^a-z0-9]', '', 'gi'));
$$;

-- ── Main RPC ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION search_global_index(
  p_query   text,
  p_limit   int DEFAULT 50
)
RETURNS TABLE (
  result_type       text,
  record_id         text,
  primary_label     text,
  secondary_label   text,
  status            text,
  matched_field     text,
  group_name        text,
  account_name      text,
  created_at        timestamptz,
  navigation_target text,
  navigation_id     text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid             uuid;
  v_profile_id      uuid;
  v_role_name       text;
  v_role_norm       text;
  v_has_full_access bool;
  v_query_clean     text;
  v_pattern         text;
  v_allowed_accts   text[];
BEGIN
  -- ── 1. Auth ──────────────────────────────────────────────────────────────
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- ── 2. Resolve caller profile & role ────────────────────────────────────
  SELECT up.id, r.role_name
  INTO v_profile_id, v_role_name
  FROM users_profile up
  JOIN roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_uid
  LIMIT 1;

  v_role_norm := _ohm_normalize_role(v_role_name);

  -- ── 3. Access gate: Data Team + superAdmin only ──────────────────────────
  IF v_role_norm NOT IN ('superadmin', 'headadmin', 'encoder') THEN
    RAISE EXCEPTION 'Access denied: Global Search is restricted to Data Team and above';
  END IF;

  -- ── 4. Full-access flag ──────────────────────────────────────────────────
  v_has_full_access := v_role_norm IN ('superadmin', 'headadmin');

  -- ── 5. Sanitize query ────────────────────────────────────────────────────
  -- Strip commas and extra whitespace
  v_query_clean := trim(regexp_replace(replace(p_query, ',', ' '), '\s+', ' ', 'g'));

  -- Reject N/A, NA, empty, or < 2 chars
  IF lower(v_query_clean) IN ('n/a', 'na', '') OR char_length(v_query_clean) < 2 THEN
    RETURN;
  END IF;

  v_pattern := '%' || upper(v_query_clean) || '%';

  -- ── 6. Resolve allowed accounts for encoder (scoped) ────────────────────
  IF NOT v_has_full_access THEN
    SELECT array_agg(DISTINCT a.account_name)
    INTO v_allowed_accts
    FROM user_scopes us
    LEFT JOIN accounts a ON a.id = us.account_id
    WHERE us.user_id = v_profile_id
      AND a.account_name IS NOT NULL;

    -- Also expand group-level scopes
    SELECT array_cat(
      v_allowed_accts,
      array_agg(DISTINCT a2.account_name)
    )
    INTO v_allowed_accts
    FROM user_scopes us2
    JOIN accounts a2 ON a2.group_id = us2.group_id
    WHERE us2.user_id = v_profile_id
      AND us2.group_id IS NOT NULL
      AND a2.account_name IS NOT NULL;

    IF v_allowed_accts IS NULL OR array_length(v_allowed_accts, 1) = 0 THEN
      RETURN; -- encoder with no scopes sees nothing
    END IF;
  END IF;

  -- ── 7. Union search with priority ordering ───────────────────────────────
  RETURN QUERY
  WITH

  -- Priority 1: exact VCODE match
  vac_exact AS (
    SELECT
      'vacancy'::text,
      v.id::text,
      v.vcode::text                                           AS primary_label,
      (COALESCE(v.position,'') || ' · ' || COALESCE(v.account,''))::text AS secondary_label,
      COALESCE(v.status,'')::text,
      'vcode'::text                                           AS matched_field,
      COALESCE(g.group_name,'')::text,
      COALESCE(v.account,'')::text,
      v.created_at::timestamptz,
      'vacancy'::text                                         AS navigation_target,
      v.vcode::text                                           AS navigation_id,
      1::int                                                  AS priority
    FROM vacancies v
    LEFT JOIN accounts ac ON lower(ac.account_name) = lower(COALESCE(v.account,''))
    LEFT JOIN groups g ON g.id = ac.group_id
    WHERE upper(v.vcode) = upper(v_query_clean)
      AND (v_has_full_access OR v.account = ANY(v_allowed_accts))
  ),

  -- Priority 2: exact emploc_no match
  emploc_exact AS (
    SELECT
      'hr_emploc'::text,
      he.id::text,
      COALESCE(he.emploc_no, he.id::text)::text,
      (COALESCE(he.applicant_name,'') || ' · ' || COALESCE(he.account,''))::text,
      COALESCE(he.status,'')::text,
      'emploc_no'::text,
      ''::text,
      COALESCE(he.account,'')::text,
      he.date_requested::timestamptz,
      'hr_emploc'::text,
      he.id::text,
      2::int
    FROM hr_emploc he
    WHERE upper(COALESCE(he.emploc_no,'')) = upper(v_query_clean)
      AND (v_has_full_access OR he.account = ANY(v_allowed_accts))
  ),

  -- Priority 3: Active plantilla employee name/no match
  plant_active AS (
    SELECT
      'plantilla'::text,
      p.id::text,
      COALESCE(p.employee_name,'')::text,
      (COALESCE(p.employee_no,'') || ' · ' || COALESCE(p.account,''))::text,
      COALESCE(p.status,'Active')::text,
      CASE
        WHEN upper(replace(COALESCE(p.employee_no,''),',',' ')) ILIKE v_pattern THEN 'employee_no'
        ELSE 'employee_name'
      END::text,
      ''::text,
      COALESCE(p.account,'')::text,
      p.created_at::timestamptz,
      'plantilla'::text,
      p.id::text,
      3::int
    FROM plantilla p
    WHERE p.status = 'Active'
      AND (
        upper(replace(COALESCE(p.employee_name,''),',',' ')) ILIKE v_pattern
        OR upper(replace(COALESCE(p.employee_no,''),',',' '))  ILIKE v_pattern
      )
      AND (v_has_full_access OR p.account = ANY(v_allowed_accts))
  ),

  -- Priority 4: HR Emploc applicant name match
  emploc_name AS (
    SELECT
      'hr_emploc'::text,
      he.id::text,
      COALESCE(he.applicant_name,'')::text,
      (COALESCE(he.emploc_no,'') || ' · ' || COALESCE(he.account,''))::text,
      COALESCE(he.status,'')::text,
      'applicant_name'::text,
      ''::text,
      COALESCE(he.account,'')::text,
      he.date_requested::timestamptz,
      'hr_emploc'::text,
      he.id::text,
      4::int
    FROM hr_emploc he
    WHERE upper(replace(COALESCE(he.applicant_name,''),',',' ')) ILIKE v_pattern
      AND upper(COALESCE(he.emploc_no,'')) != upper(v_query_clean)
      AND (v_has_full_access OR he.account = ANY(v_allowed_accts))
  ),

  -- Priority 5: Vacancy VCODE partial match
  vac_partial AS (
    SELECT
      'vacancy'::text,
      v.id::text,
      v.vcode::text,
      (COALESCE(v.position,'') || ' · ' || COALESCE(v.account,''))::text,
      COALESCE(v.status,'')::text,
      'vcode'::text,
      COALESCE(g.group_name,'')::text,
      COALESCE(v.account,'')::text,
      v.created_at::timestamptz,
      'vacancy'::text,
      v.vcode::text,
      5::int
    FROM vacancies v
    LEFT JOIN accounts ac ON lower(ac.account_name) = lower(COALESCE(v.account,''))
    LEFT JOIN groups g ON g.id = ac.group_id
    WHERE upper(v.vcode) ILIKE v_pattern
      AND upper(v.vcode) != upper(v_query_clean)
      AND (v_has_full_access OR v.account = ANY(v_allowed_accts))
  ),

  -- Priority 6: Applicant name match (linked via vacancy for scope)
  applicant_match AS (
    SELECT
      'applicant'::text,
      a.id::text,
      trim(
        COALESCE(a.first_name,'') || ' ' ||
        COALESCE(a.middle_name,'') || ' ' ||
        COALESCE(a.last_name,'')
      )::text,
      (a.vacancy_vcode || ' · ' || COALESCE(a.status,''))::text,
      COALESCE(a.status,'')::text,
      'applicant_name'::text,
      ''::text,
      COALESCE(v.account,'')::text,
      a.created_at::timestamptz,
      'vacancy'::text,
      a.vacancy_vcode::text,
      6::int
    FROM applicants a
    LEFT JOIN vacancies v ON v.vcode = a.vacancy_vcode
    WHERE upper(replace(
        trim(COALESCE(a.first_name,'') || ' ' || COALESCE(a.middle_name,'') || ' ' || COALESCE(a.last_name,'')),
        ',', ' '
      )) ILIKE v_pattern
      AND (v_has_full_access OR v.account = ANY(v_allowed_accts))
  ),

  -- Priority 7: All plantilla (inactive/deactivated) name match
  plant_all AS (
    SELECT
      'plantilla'::text,
      p.id::text,
      COALESCE(p.employee_name,'')::text,
      (COALESCE(p.employee_no,'') || ' · ' || COALESCE(p.account,''))::text,
      COALESCE(p.status,'')::text,
      CASE
        WHEN upper(replace(COALESCE(p.employee_no,''),',',' ')) ILIKE v_pattern THEN 'employee_no'
        ELSE 'employee_name'
      END::text,
      ''::text,
      COALESCE(p.account,'')::text,
      p.created_at::timestamptz,
      'plantilla'::text,
      p.id::text,
      7::int
    FROM plantilla p
    WHERE (p.status IS NULL OR p.status != 'Active')
      AND (
        upper(replace(COALESCE(p.employee_name,''),',',' ')) ILIKE v_pattern
        OR upper(replace(COALESCE(p.employee_no,''),',',' '))  ILIKE v_pattern
      )
      AND (v_has_full_access OR p.account = ANY(v_allowed_accts))
  ),

  -- Priority 8: Vacancy position/account partial match (broadest)
  vac_position AS (
    SELECT
      'vacancy'::text,
      v.id::text,
      v.vcode::text,
      (COALESCE(v.position,'') || ' · ' || COALESCE(v.account,''))::text,
      COALESCE(v.status,'')::text,
      CASE
        WHEN upper(COALESCE(v.account,'')) ILIKE v_pattern THEN 'account'
        ELSE 'position'
      END::text,
      COALESCE(g.group_name,'')::text,
      COALESCE(v.account,'')::text,
      v.created_at::timestamptz,
      'vacancy'::text,
      v.vcode::text,
      8::int
    FROM vacancies v
    LEFT JOIN accounts ac ON lower(ac.account_name) = lower(COALESCE(v.account,''))
    LEFT JOIN groups g ON g.id = ac.group_id
    WHERE (
      upper(COALESCE(v.position,'')) ILIKE v_pattern
      OR upper(COALESCE(v.account,'')) ILIKE v_pattern
    )
    AND upper(v.vcode) NOT ILIKE v_pattern
    AND (v_has_full_access OR v.account = ANY(v_allowed_accts))
  ),

  combined AS (
    SELECT * FROM vac_exact
    UNION ALL SELECT * FROM emploc_exact
    UNION ALL SELECT * FROM plant_active
    UNION ALL SELECT * FROM emploc_name
    UNION ALL SELECT * FROM vac_partial
    UNION ALL SELECT * FROM applicant_match
    UNION ALL SELECT * FROM plant_all
    UNION ALL SELECT * FROM vac_position
  ),

  -- Deduplicate: keep the highest-priority match per record
  deduped AS (
    SELECT DISTINCT ON (result_type, record_id)
      result_type, record_id, primary_label, secondary_label,
      status, matched_field, group_name, account_name,
      created_at, navigation_target, navigation_id, priority
    FROM combined
    ORDER BY result_type, record_id, priority ASC
  )

  SELECT
    d.result_type,
    d.record_id,
    d.primary_label,
    d.secondary_label,
    d.status,
    d.matched_field,
    d.group_name,
    d.account_name,
    d.created_at,
    d.navigation_target,
    d.navigation_id
  FROM deduped d
  ORDER BY d.priority ASC, d.created_at DESC NULLS LAST
  LIMIT p_limit;
END;
$$;

-- Grant execute only to authenticated users (RLS + in-function auth check handle the rest)
REVOKE EXECUTE ON FUNCTION search_global_index(text, int) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION search_global_index(text, int) TO authenticated;
