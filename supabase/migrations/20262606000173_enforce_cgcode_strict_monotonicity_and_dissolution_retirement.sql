-- ==============================================================================
-- Migration: 20262606000173_enforce_cgcode_strict_monotonicity_and_dissolution_retirement.sql
-- Description: Enforce CGCode Strict Monotonicity & Dissolution Retirement Invariant (ADR-002 Invariant 3).
--              Guarantees that when a coverage group is dissolved, merged, or archived,
--              its CGCode is permanently retired for all time.
--              Subsequent coverage groups or re-clustered roving assignments can NEVER
--              reuse, recycle, or resurrect old CGCodes — they strictly receive fresh,
--              monotonically incremental sequential CGCodes (e.g. CG-FG1-0007 -> CG-FG1-0008).
-- ==============================================================================

-- 1. Permanent Global Uniqueness Constraint across Active AND Archived Coverage Groups
-- Drops partial unique index limitation; enforces that an account can never have duplicate
-- coverage_codes even across different lifecycle states or historical records.
CREATE UNIQUE INDEX IF NOT EXISTS uq_coverage_groups_account_code_permanent
  ON public.coverage_groups (account_id, coverage_code);

-- 2. Update fn_generate_cgcode_for_account to probe across ALL historical coverage groups
-- (Omits 'archived_at IS NULL' bypass, permanently retiring all archived / dissolved codes).
CREATE OR REPLACE FUNCTION public.fn_generate_cgcode_for_account(p_account_id uuid)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $fn$
DECLARE
  v_account_name    text;
  v_group_code      text;
  v_account_initial text;
  v_prefix          text;
  v_next_seq        integer;
  v_cgcode          text;
BEGIN
  SELECT a.account_name, g.group_code
    INTO v_account_name, v_group_code
  FROM public.accounts a
  JOIN public.groups g ON g.id = a.group_id
  WHERE a.id = p_account_id;

  IF v_account_name IS NULL THEN
    RAISE EXCEPTION 'account not found for account_id: %', p_account_id;
  END IF;

  IF nullif(trim(coalesce(v_group_code, '')), '') IS NULL THEN
    RAISE EXCEPTION 'group_code not set for account_id: %', p_account_id;
  END IF;

  v_account_initial := upper(left(regexp_replace(trim(v_account_name), '[^A-Za-z0-9]', '', 'g'), 1));

  IF nullif(v_account_initial, '') IS NULL THEN
    RAISE EXCEPTION 'account initial could not be generated for account_id: %', p_account_id;
  END IF;

  -- CGCODE format: CG-<AccountInitial><GroupCode>-NNNN
  -- e.g. CG-AG1-0001. The CG- prefix is mandatory (RA1 CHECK) and
  -- visually disjoint from the VCODE family (VC…).
  v_prefix := 'CG-' || v_account_initial || upper(trim(v_group_code));

  INSERT INTO public.cgcode_sequences (prefix, last_seq, updated_at)
  VALUES (v_prefix, 1, now())
  ON CONFLICT (prefix) DO UPDATE
    SET last_seq   = public.cgcode_sequences.last_seq + 1,
        updated_at = now()
  RETURNING last_seq INTO v_next_seq;

  v_cgcode := v_prefix || '-' || lpad(v_next_seq::text, 4, '0');

  -- ADR-002 Invariant 3: Strict Monotonicity & Dissolution Retirement Invariant
  -- Dissolved, merged, and archived coverage groups are permanently retired and can NEVER be reused.
  -- Recheck against ALL historical coverage codes for this account (BOTH active AND archived).
  WHILE EXISTS (
    SELECT 1 FROM public.coverage_groups
    WHERE account_id = p_account_id
      AND coverage_code = v_cgcode
  ) LOOP
    UPDATE public.cgcode_sequences
       SET last_seq = last_seq + 1, updated_at = now()
     WHERE prefix = v_prefix
    RETURNING last_seq INTO v_next_seq;

    v_cgcode := v_prefix || '-' || lpad(v_next_seq::text, 4, '0');
  END LOOP;

  RETURN v_cgcode;
END
$fn$;

COMMENT ON FUNCTION public.fn_generate_cgcode_for_account(uuid) IS
  'Mints a strictly monotonic, sequential CG-prefixed coverage code unique per account across ALL time. '
  'Dissolved and archived codes are permanently retired and can never be reused. SECURITY DEFINER, service-role/RPC-only.';

REVOKE ALL ON FUNCTION public.fn_generate_cgcode_for_account(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_generate_cgcode_for_account(uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.fn_generate_cgcode_for_account(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_generate_cgcode_for_account(uuid) TO service_role;

-- 3. Sequence Alignment Verification
-- Ensures all sequence counters are strictly ahead of the maximum historical numeric suffix.
DO $$
DECLARE
  r RECORD;
  v_max_seq integer;
BEGIN
  FOR r IN (SELECT DISTINCT prefix FROM public.cgcode_sequences) LOOP
    SELECT COALESCE(MAX(NULLIF(regexp_replace(coverage_code, '^' || r.prefix || '-0*', ''), '')::integer), 0)
    INTO v_max_seq
    FROM public.coverage_groups
    WHERE coverage_code LIKE r.prefix || '-%';

    IF v_max_seq > 0 THEN
      UPDATE public.cgcode_sequences
      SET last_seq = GREATEST(last_seq, v_max_seq),
          updated_at = now()
      WHERE prefix = r.prefix;
    END IF;
  END LOOP;
END $$;
