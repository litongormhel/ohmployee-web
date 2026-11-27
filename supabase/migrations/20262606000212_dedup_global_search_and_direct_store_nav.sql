-- Migration: 20262606000212_dedup_global_search_and_direct_store_nav.sql
-- Created: 2026-11-27T09:40:55.000Z
-- Description: Dedup Global Search employees to strictly single current-state occurrence and add direct Store search navigation

BEGIN;

CREATE OR REPLACE FUNCTION public.search_global_index(p_query text, p_limit integer DEFAULT 50)
 RETURNS TABLE(
   result_type text,
   record_id text,
   primary_label text,
   secondary_label text,
   status text,
   matched_field text,
   group_name text,
   account_name text,
   created_at timestamp with time zone,
   navigation_target text,
   navigation_id text
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
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

  -- ── 7. Union search with priority ordering & lifecycle precedence ─────────
  RETURN QUERY
  WITH

  -- Store match (exact VCODE, exact store name, partial store name/VCODE)
  store_match AS (
    SELECT
      'store'::text                                           AS result_type,
      s.id::text                                              AS record_id,
      s.store_name::text                                      AS primary_label,
      (COALESCE(s.vcode,'') || ' · ' || COALESCE(ac.account_name,''))::text AS secondary_label,
      CASE WHEN COALESCE(s.is_archived, false) OR NOT COALESCE(s.is_active, true) THEN 'Archived' ELSE 'Active' END::text AS status,
      CASE 
        WHEN upper(COALESCE(s.vcode,'')) = upper(v_query_clean) THEN 'vcode'
        WHEN upper(s.store_name) ILIKE v_pattern THEN 'store_name'
        ELSE 'vcode'
      END::text                                               AS matched_field,
      COALESCE(g.group_name,'')::text                        AS group_name,
      COALESCE(ac.account_name,'')::text                     AS account_name,
      s.created_at::timestamptz                               AS created_at,
      'store'::text                                           AS navigation_target,
      COALESCE(s.vcode, s.id::text)::text                     AS navigation_id,
      CASE 
        WHEN upper(COALESCE(s.vcode,'')) = upper(v_query_clean) THEN 1
        WHEN upper(s.store_name) = upper(v_query_clean) THEN 1
        ELSE 2
      END::int                                                AS priority,
      'store::' || lower(s.id::text)                          AS dedup_key
    FROM stores s
    LEFT JOIN accounts ac ON ac.id = s.account_id
    LEFT JOIN groups g ON g.id = ac.group_id
    WHERE (
      upper(COALESCE(s.vcode,'')) = upper(v_query_clean)
      OR upper(s.store_name) ILIKE v_pattern
      OR upper(COALESCE(s.vcode,'')) ILIKE v_pattern
    )
    AND (v_has_full_access OR ac.account_name = ANY(v_allowed_accts))
  ),

  -- Priority 1: exact VCODE match on vacancies
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
      1::int                                                  AS priority,
      'vacancy::' || lower(v.vcode)                           AS dedup_key
    FROM vacancies v
    LEFT JOIN accounts ac ON lower(ac.account_name) = lower(COALESCE(v.account,''))
    LEFT JOIN groups g ON g.id = ac.group_id
    WHERE upper(v.vcode) = upper(v_query_clean)
      AND (v_has_full_access OR v.account = ANY(v_allowed_accts))
  ),

  -- Priority 2: exact emploc_no match (Active Emploc only - not yet in Plantilla)
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
      2::int,
      'person::' || COALESCE(
        NULLIF(upper(trim(he.emploc_no)), ''),
        upper(trim(COALESCE(he.account,''))) || '::' || upper(trim(he.applicant_name))
      ) AS dedup_key
    FROM hr_emploc he
    WHERE upper(COALESCE(he.emploc_no,'')) = upper(v_query_clean)
      AND (v_has_full_access OR he.account = ANY(v_allowed_accts))
      AND he.status != 'Moved to Plantilla'
      AND NOT EXISTS (
        SELECT 1 FROM plantilla p 
        WHERE p.hr_emploc_id = he.id 
           OR (he.emploc_no IS NOT NULL AND p.emploc_no = he.emploc_no)
           OR (he.applicant_name IS NOT NULL AND upper(trim(p.employee_name)) = upper(trim(he.applicant_name)))
      )
  ),

  -- Priority 3: Current Plantilla employees (Active, On-Leave, Floating, Deactivation)
  plant_current AS (
    SELECT
      'plantilla'::text,
      p.id::text,
      COALESCE(p.employee_name,'')::text,
      (COALESCE(p.employee_no,'') || ' · ' || COALESCE(p.account,''))::text,
      COALESCE(p.status,'Active')::text,
      CASE
        WHEN upper(replace(COALESCE(p.employee_no,''),',',' ')) ILIKE v_pattern THEN 'employee_no'
        WHEN upper(replace(COALESCE(p.emploc_no,''),',',' ')) ILIKE v_pattern THEN 'emploc_no'
        ELSE 'employee_name'
      END::text,
      ''::text,
      COALESCE(p.account,'')::text,
      p.created_at::timestamptz,
      'plantilla'::text,
      p.id::text,
      CASE 
        WHEN upper(COALESCE(p.employee_no,'')) = upper(v_query_clean) THEN 2
        WHEN upper(COALESCE(p.emploc_no,'')) = upper(v_query_clean) THEN 2
        ELSE 3
      END::int,
      'person::' || COALESCE(
        NULLIF(trim(upper(p.employee_no)), ''),
        NULLIF(trim(upper(p.emploc_no)), ''),
        trim(upper(COALESCE(p.account,''))) || '::' || trim(upper(p.employee_name))
      ) AS dedup_key
    FROM plantilla p
    WHERE (p.status IS NULL OR p.status IN ('Active', 'On-Leave', 'On Leave', 'Floating', 'Deactivation', 'Pending Deactivation'))
      AND (
        upper(replace(COALESCE(p.employee_name,''),',',' ')) ILIKE v_pattern
        OR upper(replace(COALESCE(p.employee_no,''),',',' '))  ILIKE v_pattern
        OR upper(replace(COALESCE(p.emploc_no,''),',',' '))  ILIKE v_pattern
      )
      AND (v_has_full_access OR p.account = ANY(v_allowed_accts))
  ),

  -- Priority 4: Inactive/Deactivated Plantilla employees (lower priority than active, deduped per person)
  plant_inactive AS (
    SELECT
      'plantilla'::text,
      p.id::text,
      COALESCE(p.employee_name,'')::text,
      (COALESCE(p.employee_no,'') || ' · ' || COALESCE(p.account,''))::text,
      COALESCE(p.status,'Inactive')::text,
      CASE
        WHEN upper(replace(COALESCE(p.employee_no,''),',',' ')) ILIKE v_pattern THEN 'employee_no'
        WHEN upper(replace(COALESCE(p.emploc_no,''),',',' ')) ILIKE v_pattern THEN 'emploc_no'
        ELSE 'employee_name'
      END::text,
      ''::text,
      COALESCE(p.account,'')::text,
      p.created_at::timestamptz,
      'plantilla'::text,
      p.id::text,
      CASE 
        WHEN upper(COALESCE(p.employee_no,'')) = upper(v_query_clean) THEN 4
        WHEN upper(COALESCE(p.emploc_no,'')) = upper(v_query_clean) THEN 4
        ELSE 5
      END::int,
      'person::' || COALESCE(
        NULLIF(trim(upper(p.employee_no)), ''),
        NULLIF(trim(upper(p.emploc_no)), ''),
        trim(upper(COALESCE(p.account,''))) || '::' || trim(upper(p.employee_name))
      ) AS dedup_key
    FROM plantilla p
    WHERE p.status NOT IN ('Active', 'On-Leave', 'On Leave', 'Floating', 'Deactivation', 'Pending Deactivation')
      AND (
        upper(replace(COALESCE(p.employee_name,''),',',' ')) ILIKE v_pattern
        OR upper(replace(COALESCE(p.employee_no,''),',',' '))  ILIKE v_pattern
        OR upper(replace(COALESCE(p.emploc_no,''),',',' '))  ILIKE v_pattern
      )
      AND (v_has_full_access OR p.account = ANY(v_allowed_accts))
  ),

  -- Priority 5: HR Emploc active onboarding candidate match (exclude if already in Plantilla)
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
      6::int,
      'person::' || COALESCE(
        NULLIF(upper(trim(he.emploc_no)), ''),
        upper(trim(COALESCE(he.account,''))) || '::' || upper(trim(he.applicant_name))
      ) AS dedup_key
    FROM hr_emploc he
    WHERE upper(replace(COALESCE(he.applicant_name,''),',',' ')) ILIKE v_pattern
      AND upper(COALESCE(he.emploc_no,'')) != upper(v_query_clean)
      AND (v_has_full_access OR he.account = ANY(v_allowed_accts))
      AND he.status != 'Moved to Plantilla'
      AND NOT EXISTS (
        SELECT 1 FROM plantilla p 
        WHERE p.hr_emploc_id = he.id 
           OR (he.emploc_no IS NOT NULL AND p.emploc_no = he.emploc_no)
           OR (he.applicant_name IS NOT NULL AND upper(trim(p.employee_name)) = upper(trim(he.applicant_name)))
      )
  ),

  -- Priority 6: Vacancy VCODE partial match
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
      6::int,
      'vacancy::' || lower(v.vcode)                           AS dedup_key
    FROM vacancies v
    LEFT JOIN accounts ac ON lower(ac.account_name) = lower(COALESCE(v.account,''))
    LEFT JOIN groups g ON g.id = ac.group_id
    WHERE upper(v.vcode) ILIKE v_pattern
      AND upper(v.vcode) != upper(v_query_clean)
      AND (v_has_full_access OR v.account = ANY(v_allowed_accts))
  ),

  -- Priority 7: Pipeline Applicant name match (exclude if already in HR Emploc or Plantilla)
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
      7::int,
      'person::' || trim(upper(COALESCE(a.first_name,'') || ' ' || COALESCE(a.last_name,''))) AS dedup_key
    FROM applicants a
    LEFT JOIN vacancies v ON v.vcode = a.vacancy_vcode
    WHERE upper(replace(
        trim(COALESCE(a.first_name,'') || ' ' || COALESCE(a.middle_name,'') || ' ' || COALESCE(a.last_name,'')),
        ',', ' '
      )) ILIKE v_pattern
      AND (v_has_full_access OR v.account = ANY(v_allowed_accts))
      AND NOT EXISTS (
        SELECT 1 FROM hr_emploc he WHERE he.applicant_id = a.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM plantilla p 
        WHERE p.id = a.linked_plantilla_id
           OR p.hr_emploc_id IN (SELECT he2.id FROM hr_emploc he2 WHERE he2.applicant_id = a.id)
           OR upper(trim(p.employee_name)) = upper(trim(COALESCE(a.first_name,'') || ' ' || COALESCE(a.middle_name,'') || ' ' || COALESCE(a.last_name,'')))
           OR upper(trim(p.employee_name)) = upper(trim(COALESCE(a.last_name,'') || ', ' || COALESCE(a.first_name,'') || ' ' || COALESCE(a.middle_name,'')))
           OR upper(trim(p.employee_name)) = upper(trim(COALESCE(a.last_name,'') || ', ' || COALESCE(a.first_name,'')))
      )
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
      8::int,
      'vacancy::' || lower(v.vcode)                           AS dedup_key
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

  combined(result_type, record_id, primary_label, secondary_label, status, matched_field, group_name, account_name, created_at, navigation_target, navigation_id, priority, dedup_key) AS (
    SELECT * FROM store_match
    UNION ALL SELECT * FROM vac_exact
    UNION ALL SELECT * FROM emploc_exact
    UNION ALL SELECT * FROM plant_current
    UNION ALL SELECT * FROM plant_inactive
    UNION ALL SELECT * FROM emploc_name
    UNION ALL SELECT * FROM vac_partial
    UNION ALL SELECT * FROM applicant_match
    UNION ALL SELECT * FROM vac_position
  ),

  -- Deduplicate: keep the single highest-priority (current state) match per person/store/vacancy
  deduped AS (
    SELECT DISTINCT ON (c.dedup_key)
      c.result_type,
      c.record_id,
      c.primary_label,
      c.secondary_label,
      c.status,
      c.matched_field,
      c.group_name,
      c.account_name,
      c.created_at,
      c.navigation_target,
      c.navigation_id,
      c.priority
    FROM combined c
    ORDER BY c.dedup_key, c.priority ASC, c.created_at DESC NULLS LAST
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
$function$;

REVOKE EXECUTE ON FUNCTION public.search_global_index(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_global_index(text, integer) TO authenticated;

COMMIT;
