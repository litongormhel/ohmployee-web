-- Migration: 20262606000211_normalize_demographics_and_stores.sql
-- Module: Plantilla, Vacancy, Stores (Demographics & Store Formatting)
-- Purpose:
--   1. Create immutable function public.fn_format_store_name(text) implementing Title Case formatting
--      with strict uppercase preservation for retail and location acronyms (SM, SSM, SMC, S&R, PG, MOA,
--      EDSA, FTI, QC, HQ, NCR, NCCC, RDS, GMC, GMA, CSI, KCC, LCC, etc.) and Filipino orthography (Ñ/ñ).
--   2. Normalize store_name, area_city, and area_province in public.stores and synchronize child
--      snapshot tables (plantilla, vacancies, hr_emploc, employee_store_allocations, headcount_requests).
--   3. Reconcile dangling last_mika_synced_by, normalize plantilla.civil_status to canonical Title Case
--      ('Single', 'Married', 'Widowed', 'Separated', 'Divorced'), nullify dirty values ('0', 'N/A', 'None'),
--      and add plantilla_civil_status_check.
--   4. Normalize plantilla.deployment_type ('commando' -> 'Commando') and add plantilla_deployment_type_check.

-- ============================================================================
-- 1. Create public.fn_format_store_name(text)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_format_store_name(p_text text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_trimmed text;
  v_token text;
  v_result text := '';
  v_upper text;
  v_known_acronyms text[] := ARRAY[
    'SM', 'SSM', 'SMC', 'S&R', 'PG', 'MOA', 'EDSA', 'FTI', 'QC', 'HQ', 'NCR',
    'NCCC', 'RDS', 'GMC', 'GMA', 'CSI', 'KCC', 'LCC', 'EMALL', 'GMALL', 'JY', 'JS',
    'CB', 'VM', 'D''MALL', 'E-MALL', 'G-MALL', 'BGC', 'CBD', 'ATC', 'AYALA', 'MIT', 'CIT'
  ];
  v_common_3words text[] := ARRAY[
    'NEW', 'OLD', 'SAN', 'STA', 'STO', 'THE', 'DEL', 'LAS', 'LOS', 'ONE', 'ALL', 'BIG', 'TOP', 'HUB', 'BAY', 'ROW', 'WAY', 'DAY', 'TWO', 'SIX', 'TEN'
  ];
BEGIN
  IF p_text IS NULL OR TRIM(p_text) = '' THEN
    RETURN p_text;
  END IF;

  -- Remove obsolete [roving] tag
  v_trimmed := TRIM(REGEXP_REPLACE(p_text, '\s*\[roving\]\s*', ' ', 'gi'));

  -- Match tokens: words (including & and Ñ/ñ) or whitespace/punctuation
  FOR v_token IN SELECT (regexp_matches(v_trimmed, '([a-zA-Z0-9&''Ññ]+|[^a-zA-Z0-9&''Ññ]+)', 'g'))[1] LOOP
    IF v_token ~ '^[a-zA-Z0-9&''Ññ]+$' THEN
      -- Token contains digits: preserve raw
      IF v_token ~ '[0-9]' THEN
        v_result := v_result || v_token;
      ELSE
        v_upper := UPPER(v_token);
        -- Check known acronyms allowlist first
        IF v_upper = ANY(v_known_acronyms) THEN
          v_result := v_result || v_upper;
        ELSIF v_upper = ANY(v_common_3words) THEN
          v_result := v_result || INITCAP(v_token);
        ELSIF LENGTH(v_token) = 2 AND v_upper NOT IN ('AT', 'IN', 'ON', 'TO', 'BY', 'OF', 'AN', 'AS', 'OR') THEN
          -- 2-letter non-preposition abbreviation -> UPPERCASE (e.g. SM, PG, QC)
          v_result := v_result || v_upper;
        ELSE
          -- Title case for words (handle Mc prefix)
          IF v_upper LIKE 'MC%' AND LENGTH(v_token) > 2 THEN
            v_result := v_result || 'Mc' || INITCAP(SUBSTRING(v_token FROM 3));
          ELSE
            v_result := v_result || INITCAP(v_token);
          END IF;
        END IF;
      END IF;
    ELSE
      v_result := v_result || v_token;
    END IF;
  END LOOP;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.fn_format_store_name(text) IS
'Deterministic store name and location formatter enforcing Title Case with strict uppercase acronym preservation (SM, SSM, S&R, MOA, EDSA, FTI, QC, NCCC, etc.) and Filipino orthography (Ñ/ñ).';

-- ============================================================================
-- 2. Normalize Stores & Location Names
-- ============================================================================
UPDATE public.stores
SET
  store_name = public.fn_format_store_name(store_name),
  area_city = CASE WHEN area_city IS NOT NULL THEN public.fn_format_store_name(area_city) ELSE NULL END,
  area_province = CASE WHEN area_province IS NOT NULL THEN public.fn_format_store_name(area_province) ELSE NULL END
WHERE is_archived = false;

-- Synchronize child snapshot tables
UPDATE public.plantilla
SET store_name = public.fn_format_store_name(store_name)
WHERE store_name IS NOT NULL
  AND store_name != public.fn_format_store_name(store_name);

UPDATE public.vacancies
SET
  store_name = CASE WHEN store_name IS NOT NULL THEN public.fn_format_store_name(store_name) ELSE NULL END,
  area_city = CASE WHEN area_city IS NOT NULL THEN public.fn_format_store_name(area_city) ELSE NULL END
WHERE (store_name IS NOT NULL AND store_name != public.fn_format_store_name(store_name))
   OR (area_city IS NOT NULL AND area_city != public.fn_format_store_name(area_city));

UPDATE public.hr_emploc
SET store_name = public.fn_format_store_name(store_name)
WHERE store_name IS NOT NULL
  AND store_name != public.fn_format_store_name(store_name);

UPDATE public.employee_store_allocations
SET store_name = public.fn_format_store_name(store_name)
WHERE store_name IS NOT NULL
  AND store_name != public.fn_format_store_name(store_name);

UPDATE public.headcount_requests
SET store_name_snapshot = public.fn_format_store_name(store_name_snapshot)
WHERE store_name_snapshot IS NOT NULL
  AND store_name_snapshot != public.fn_format_store_name(store_name_snapshot);

-- ============================================================================
-- 3. Reconcile Dangling User FKs & Normalize Plantilla Demographics
-- ============================================================================
-- Nullify dangling last_mika_synced_by references to satisfy plantilla_last_mika_synced_by_fkey
UPDATE public.plantilla
SET last_mika_synced_by = NULL
WHERE last_mika_synced_by IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = plantilla.last_mika_synced_by);

-- Normalize civil_status on rows requiring updates
UPDATE public.plantilla
SET civil_status = CASE
  WHEN LOWER(TRIM(civil_status)) = 'single' THEN 'Single'
  WHEN LOWER(TRIM(civil_status)) = 'married' THEN 'Married'
  WHEN LOWER(TRIM(civil_status)) IN ('widowed', 'widow', 'widower') THEN 'Widowed'
  WHEN LOWER(TRIM(civil_status)) = 'separated' THEN 'Separated'
  WHEN LOWER(TRIM(civil_status)) = 'divorced' THEN 'Divorced'
  WHEN TRIM(civil_status) IN ('0', 'N/A', 'n/a', 'NA', 'na', 'None', 'NONE', '') THEN NULL
  ELSE INITCAP(TRIM(civil_status))
END
WHERE civil_status IS NOT NULL
  AND (civil_status NOT IN ('Single', 'Married', 'Widowed', 'Separated', 'Divorced')
       OR TRIM(civil_status) IN ('0', 'N/A', 'n/a', 'NA', 'na', 'None', 'NONE', ''));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'plantilla_civil_status_check'
      AND conrelid = 'public.plantilla'::regclass
  ) THEN
    ALTER TABLE public.plantilla
      ADD CONSTRAINT plantilla_civil_status_check
      CHECK (civil_status IS NULL OR civil_status = ANY (ARRAY['Single'::text, 'Married'::text, 'Widowed'::text, 'Separated'::text, 'Divorced'::text])) NOT VALID;
  END IF;
END $$;

-- ============================================================================
-- 4. Normalize Plantilla Deployment Type
-- ============================================================================
UPDATE public.plantilla
SET deployment_type = CASE
  WHEN LOWER(TRIM(deployment_type)) = 'stationary' THEN 'Stationary'
  WHEN LOWER(TRIM(deployment_type)) = 'roving' THEN 'Roving'
  WHEN LOWER(TRIM(deployment_type)) = 'commando' THEN 'Commando'
  ELSE INITCAP(TRIM(deployment_type))
END
WHERE deployment_type IS NOT NULL
  AND deployment_type NOT IN ('Stationary', 'Roving', 'Commando');

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'plantilla_deployment_type_check'
      AND conrelid = 'public.plantilla'::regclass
  ) THEN
    ALTER TABLE public.plantilla
      ADD CONSTRAINT plantilla_deployment_type_check
      CHECK (deployment_type IS NULL OR deployment_type = ANY (ARRAY['Stationary'::text, 'Roving'::text, 'Commando'::text])) NOT VALID;
  END IF;
END $$;
