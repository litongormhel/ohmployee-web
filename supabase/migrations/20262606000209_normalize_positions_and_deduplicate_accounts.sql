-- Migration: 20262606000209_normalize_positions_and_deduplicate_accounts.sql
-- Description: Consolidate duplicate master positions, deduplicate account_positions,
--              enforce case-insensitive uniqueness, format historical position strings,
--              and implement fn_format_position_title enforcing Title Case + 2-3 letter UPPERCASE rule.

-- 1. Helper function for consistent position title formatting
CREATE OR REPLACE FUNCTION public.fn_format_position_title(p_text text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_trimmed text;
  v_formatted text;
BEGIN
  IF p_text IS NULL OR TRIM(p_text) = '' THEN
    RETURN p_text;
  END IF;

  v_trimmed := TRIM(p_text);

  SELECT string_agg(
    CASE 
      -- Delimiters / whitespace / punctuation preserved as-is
      WHEN m[1] ~ '^[ \t\r\n,/()\-.]+$' THEN m[1]
      -- Tokens containing any digit preserved as-is (e.g. 3WAY, CREW 3)
      WHEN m[1] ~ '\d' THEN m[1]
      -- Acronyms in allowlist (4+ letters) -> UPPERCASE
      WHEN UPPER(m[1]) IN ('HRCO', 'CENCOM', 'VCODE', 'RLS', 'RPC', 'ADR', 'SLA', 'FMCG') THEN UPPER(m[1])
      -- 2 to 3 alphabetic letters -> UPPERCASE all (e.g. FSR, SMP, AR, GL, QA, TL, OM, ATL, HR, IT, CSR, TSR, HQ, SM)
      WHEN m[1] ~* '^[a-z]{2,3}$' THEN UPPER(m[1])
      -- Otherwise Proper Case (Initial letter capital, rest lowercase)
      ELSE UPPER(SUBSTRING(m[1] FROM 1 FOR 1)) || LOWER(SUBSTRING(m[1] FROM 2))
    END,
    ''
  ) INTO v_formatted
  FROM regexp_matches(v_trimmed, '([a-zA-Z0-9]+|[ \t\r\n,/()\-.]+)', 'g') AS m;

  RETURN COALESCE(v_formatted, v_trimmed);
END;
$$;

-- 2. Consolidate and merge the 5 duplicate uppercase positions into canonical Proper Case records
DO $$
DECLARE
  v_merges jsonb := '[
    {"deprecated": "acbcd7ed-4aaf-4203-8bbf-7a7877c0f62e", "canonical": "e23a9bfb-db0c-4921-a3b4-75c6e0981f53", "name": "Merchandiser"},
    {"deprecated": "75dba2a7-6bac-4a36-8718-28b2920c5734", "canonical": "59b5b079-a920-414d-805e-c6051e5d1cd5", "name": "Cashier"},
    {"deprecated": "9af1bb1f-5ebc-439b-b259-6085cc47c9cb", "canonical": "01983f43-0659-4294-9741-dd470224f137", "name": "Promodiser"},
    {"deprecated": "f8be7c5f-8358-4181-8a22-afc6a9475b40", "canonical": "dff13db0-2e13-4402-8547-3bd065717bfb", "name": "Inventory Clerk"},
    {"deprecated": "213504a3-1095-4594-91fc-ba6e9ee50d77", "canonical": "7954636c-0100-4eb4-ba7d-0920ea4aede3", "name": "Service Crew"}
  ]'::jsonb;
  v_item jsonb;
  v_dep uuid;
  v_can uuid;
BEGIN
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_merges)
  LOOP
    v_dep := (v_item->>'deprecated')::uuid;
    v_can := (v_item->>'canonical')::uuid;

    -- a. In account_positions: remove duplicate if account already has canonical
    DELETE FROM public.account_positions
    WHERE position_id = v_dep
      AND account_id IN (
        SELECT account_id FROM public.account_positions WHERE position_id = v_can
      );

    -- b. Update remaining account_positions to canonical ID
    UPDATE public.account_positions
    SET position_id = v_can
    WHERE position_id = v_dep;

    -- c. Update all child foreign keys and references
    UPDATE public.plantilla SET position_id = v_can WHERE position_id = v_dep;
    UPDATE public.vacancies SET position_id = v_can WHERE position_id = v_dep;
    UPDATE public.hr_emploc SET position_id_snapshot = v_can WHERE position_id_snapshot = v_dep;
    UPDATE public.headcount_requests SET position_id = v_can WHERE position_id = v_dep;
    UPDATE public.coverage_groups SET position_id = v_can WHERE position_id = v_dep;
    UPDATE public.coverage_requests SET position_id = v_can WHERE position_id = v_dep;
    UPDATE public.headcount_quota_revisions SET position_id = v_can WHERE position_id = v_dep;
    UPDATE public.workforce_pool_request_items SET position_id = v_can WHERE position_id = v_dep;
    UPDATE public.employee_transfers SET target_position_id = v_can WHERE target_position_id = v_dep;

    -- d. Safely remove deprecated position row
    DELETE FROM public.positions WHERE id = v_dep;
  END LOOP;
END $$;

-- 3. Eliminate any residual duplicates in account_positions and enforce unique index
DELETE FROM public.account_positions a
WHERE a.id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY account_id, position_id ORDER BY created_at ASC) as rn
    FROM public.account_positions
  ) sub
  WHERE rn > 1
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_account_positions_account_position
ON public.account_positions (account_id, position_id);

-- 4. Normalize all existing names in public.positions to Proper Case + 2-3 Letter UPPERCASE
UPDATE public.positions
SET position_name = public.fn_format_position_title(position_name)
WHERE position_name IS NOT NULL
  AND position_name != public.fn_format_position_title(position_name);

-- 5. Enforce case-insensitive uniqueness on public.positions to prevent future duplication
CREATE UNIQUE INDEX IF NOT EXISTS uq_positions_normalized_name
ON public.positions (LOWER(TRIM(position_name)));

-- 6. Format historical position strings across all operational tables
UPDATE public.plantilla
SET position = public.fn_format_position_title(position)
WHERE position IS NOT NULL
  AND position != public.fn_format_position_title(position);

UPDATE public.vacancies
SET position = public.fn_format_position_title(position)
WHERE position IS NOT NULL
  AND position != public.fn_format_position_title(position);

UPDATE public.plantilla_slots
SET position = public.fn_format_position_title(position)
WHERE position IS NOT NULL
  AND position != public.fn_format_position_title(position);

UPDATE public.hr_emploc
SET position = public.fn_format_position_title(position)
WHERE position IS NOT NULL
  AND position != public.fn_format_position_title(position);

UPDATE public.headcount_requests
SET position_name_snapshot = public.fn_format_position_title(position_name_snapshot)
WHERE position_name_snapshot IS NOT NULL
  AND position_name_snapshot != public.fn_format_position_title(position_name_snapshot);
