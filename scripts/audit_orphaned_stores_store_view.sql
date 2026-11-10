-- ============================================================================
-- Store View Data Audit & Orphaned Store Identification Script
-- Purpose:
--   Audits stores displaying in the Plantilla Store View to ensure that ONLY
--   stores with at least one record in the following states are populated:
--     1. Active employees (plantilla.status = 'Active')
--     2. On-Leave employees (plantilla.status IN ('On Leave', 'on_leave'))
--     3. Open Vacancies (vacancies.status = 'Open' AND NOT is_archived AND deleted_at IS NULL)
--
--   Identifies orphaned stores (e.g., Festival Mall, SM Caloocan) that have
--   0 Active, 0 On-Leave, and 0 Vacancies, and reconciles stores with active
--   personnel deployed (e.g., 'Super 8 Dau') whose store_id may be NULL.
--
-- Target Database: STAGING (qqiiznmqxfoamqytjica) / PRODUCTION (rwxelulyapjgaarlwkus)
-- Safe: READ-ONLY AUDIT by default. Includes optional archive DML at the bottom.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- SECTION 1: Scoped Audit Query for a Specific Account (e.g., ACTISERVE)
-- ----------------------------------------------------------------------------

WITH target_account AS (
  SELECT '4fba7c47-f19e-47fb-9074-6acab754721f'::uuid AS account_id
),
store_active AS (
  SELECT
    LOWER(TRIM(p.store_name)) AS store_key,
    COUNT(*) AS active_count
  FROM public.plantilla p
  JOIN target_account ta ON p.account_id = ta.account_id
  WHERE LOWER(TRIM(p.status)) = 'active'
    AND p.deactivated_at IS NULL
    AND p.date_of_separation IS NULL
    AND p.store_name IS NOT NULL
  GROUP BY LOWER(TRIM(p.store_name))
),
store_on_leave AS (
  SELECT
    LOWER(TRIM(p.store_name)) AS store_key,
    COUNT(*) AS on_leave_count
  FROM public.plantilla p
  JOIN target_account ta ON p.account_id = ta.account_id
  WHERE LOWER(TRIM(p.status)) IN ('on leave', 'on_leave')
    AND p.deactivated_at IS NULL
    AND p.date_of_separation IS NULL
    AND p.store_name IS NOT NULL
  GROUP BY LOWER(TRIM(p.store_name))
),
store_vacancies AS (
  SELECT
    LOWER(TRIM(v.store_name)) AS store_key,
    COUNT(*) AS open_vacancies
  FROM public.vacancies v
  JOIN target_account ta ON v.account_id = ta.account_id
  WHERE v.deleted_at IS NULL
    AND COALESCE(v.is_archived, FALSE) = FALSE
    AND LOWER(TRIM(v.status)) = 'open'
    AND v.store_name IS NOT NULL
  GROUP BY LOWER(TRIM(v.store_name))
),
all_account_stores AS (
  -- Stores registered in public.stores
  SELECT
    s.id AS store_id,
    s.store_name,
    s.vcode,
    s.area_city,
    COALESCE(s.province, s.area_province) AS province,
    LOWER(TRIM(s.store_name)) AS store_key,
    TRUE AS registered_in_stores_table
  FROM public.stores s
  JOIN target_account ta ON s.account_id = ta.account_id
  WHERE s.is_active = TRUE

  UNION

  -- Stores active in plantilla (e.g., Super 8 Dau where store_id is NULL)
  SELECT
    p.store_id,
    p.store_name,
    p.vcode,
    NULL AS area_city,
    p.area AS province,
    LOWER(TRIM(p.store_name)) AS store_key,
    (p.store_id IS NOT NULL) AS registered_in_stores_table
  FROM public.plantilla p
  JOIN target_account ta ON p.account_id = ta.account_id
  WHERE LOWER(TRIM(p.status)) IN ('active', 'on leave', 'on_leave')
    AND p.deactivated_at IS NULL
    AND p.date_of_separation IS NULL
    AND p.store_name IS NOT NULL

  UNION

  -- Stores active in vacancies
  SELECT
    v.store_id,
    v.store_name,
    v.vcode,
    NULL AS area_city,
    NULL AS province,
    LOWER(TRIM(v.store_name)) AS store_key,
    (v.store_id IS NOT NULL) AS registered_in_stores_table
  FROM public.vacancies v
  JOIN target_account ta ON v.account_id = ta.account_id
  WHERE v.deleted_at IS NULL
    AND COALESCE(v.is_archived, FALSE) = FALSE
    AND LOWER(TRIM(v.status)) = 'open'
    AND v.store_name IS NOT NULL
),
consolidated_stores AS (
  SELECT
    store_key,
    MAX(store_name) AS store_name,
    MAX(store_id::text)::uuid AS store_id,
    MAX(vcode) AS vcode,
    MAX(area_city) AS area_city,
    MAX(province) AS province,
    BOOL_OR(registered_in_stores_table) AS registered_in_stores_table
  FROM all_account_stores
  GROUP BY store_key
)
SELECT
  cs.store_name,
  cs.vcode,
  COALESCE(cs.area_city, '—') AS area_city,
  COALESCE(cs.province, '—') AS province,
  COALESCE(sa.active_count, 0) AS active_count,
  COALESCE(sol.on_leave_count, 0) AS on_leave_count,
  COALESCE(sv.open_vacancies, 0) AS open_vacancies,
  CASE
    WHEN COALESCE(sa.active_count, 0) = 0
     AND COALESCE(sol.on_leave_count, 0) = 0
     AND COALESCE(sv.open_vacancies, 0) = 0
    THEN 'ORPHANED (HIDE)'
    ELSE 'POPULATE (SHOW)'
  END AS store_view_action,
  cs.registered_in_stores_table
FROM consolidated_stores cs
LEFT JOIN store_active sa ON sa.store_key = cs.store_key
LEFT JOIN store_on_leave sol ON sol.store_key = cs.store_key
LEFT JOIN store_vacancies sv ON sv.store_key = cs.store_key
ORDER BY
  store_view_action DESC,
  active_count DESC,
  open_vacancies DESC,
  cs.store_name ASC;


-- ----------------------------------------------------------------------------
-- SECTION 2: Global Cross-Account Audit Query (All Active Accounts)
-- ----------------------------------------------------------------------------

WITH store_active_global AS (
  SELECT
    p.account_id,
    LOWER(TRIM(p.store_name)) AS store_key,
    COUNT(*) AS active_count
  FROM public.plantilla p
  WHERE LOWER(TRIM(p.status)) = 'active'
    AND p.deactivated_at IS NULL
    AND p.date_of_separation IS NULL
    AND p.store_name IS NOT NULL
  GROUP BY p.account_id, LOWER(TRIM(p.store_name))
),
store_on_leave_global AS (
  SELECT
    p.account_id,
    LOWER(TRIM(p.store_name)) AS store_key,
    COUNT(*) AS on_leave_count
  FROM public.plantilla p
  WHERE LOWER(TRIM(p.status)) IN ('on leave', 'on_leave')
    AND p.deactivated_at IS NULL
    AND p.date_of_separation IS NULL
    AND p.store_name IS NOT NULL
  GROUP BY p.account_id, LOWER(TRIM(p.store_name))
),
store_vacancies_global AS (
  SELECT
    v.account_id,
    LOWER(TRIM(v.store_name)) AS store_key,
    COUNT(*) AS open_vacancies
  FROM public.vacancies v
  WHERE v.deleted_at IS NULL
    AND COALESCE(v.is_archived, FALSE) = FALSE
    AND LOWER(TRIM(v.status)) = 'open'
    AND v.store_name IS NOT NULL
  GROUP BY v.account_id, LOWER(TRIM(v.store_name))
)
SELECT
  a.account_name,
  s.id AS store_id,
  s.store_name,
  s.vcode,
  s.area_city,
  COALESCE(s.province, s.area_province) AS province,
  COALESCE(sag.active_count, 0) AS active_count,
  COALESCE(solg.on_leave_count, 0) AS on_leave_count,
  COALESCE(svg.open_vacancies, 0) AS open_vacancies,
  CASE
    WHEN COALESCE(sag.active_count, 0) = 0
     AND COALESCE(solg.on_leave_count, 0) = 0
     AND COALESCE(svg.open_vacancies, 0) = 0
    THEN 'ORPHANED'
    ELSE 'POPULATE'
  END AS status
FROM public.stores s
JOIN public.accounts a ON a.id = s.account_id
LEFT JOIN store_active_global sag
  ON sag.account_id = s.account_id
 AND sag.store_key = LOWER(TRIM(s.store_name))
LEFT JOIN store_on_leave_global solg
  ON solg.account_id = s.account_id
 AND solg.store_key = LOWER(TRIM(s.store_name))
LEFT JOIN store_vacancies_global svg
  ON svg.account_id = s.account_id
 AND svg.store_key = LOWER(TRIM(s.store_name))
WHERE s.is_active = TRUE
ORDER BY status DESC, a.account_name ASC, s.store_name ASC;


-- ----------------------------------------------------------------------------
-- SECTION 3: Summary Metrics Count
-- ----------------------------------------------------------------------------

WITH store_status AS (
  SELECT
    s.id,
    s.account_id,
    CASE
      WHEN NOT EXISTS (
        SELECT 1 FROM public.plantilla p
        WHERE p.account_id = s.account_id
          AND LOWER(TRIM(p.store_name)) = LOWER(TRIM(s.store_name))
          AND LOWER(TRIM(p.status)) IN ('active', 'on leave', 'on_leave')
          AND p.deactivated_at IS NULL
          AND p.date_of_separation IS NULL
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.vacancies v
        WHERE v.account_id = s.account_id
          AND LOWER(TRIM(v.store_name)) = LOWER(TRIM(s.store_name))
          AND v.deleted_at IS NULL
          AND COALESCE(v.is_archived, FALSE) = FALSE
          AND LOWER(TRIM(v.status)) = 'open'
      )
      THEN 'ORPHANED'
      ELSE 'POPULATED'
    END AS presence_status
  FROM public.stores s
  WHERE s.is_active = TRUE
)
SELECT
  presence_status,
  COUNT(*) AS total_stores
FROM store_status
GROUP BY presence_status;
