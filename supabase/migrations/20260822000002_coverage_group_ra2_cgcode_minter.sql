-- ============================================================
-- OHM2026_0066 — Coverage Group Phase R-A — RA2 CGCODE minter
-- Migration:  20260822000002_coverage_group_ra2_cgcode_minter.sql
-- Plan:       docs/architecture/coverage_group_phase_ra_schema_plan.md (§RA2, §5)
-- Depends on: RA1 (coverage_groups), live accounts + groups.
-- ============================================================
-- Scope: CGCODE minter — peer of generate_vcode_for_account, but a
--   DISJOINT namespace. It uses its own sequence table (cgcode_sequences)
--   and never touches vcode_sequences, so a CG- code can never collide
--   with or be mistaken for a VCODE.
--
--   Guarantees (per plan §5):
--     (a) CG- prefix      → satisfied by format + RA1 CHECK (coverage_code LIKE 'CG-%')
--     (b) unique per account → upsert on the sequence + active-CGCODE recheck
--     (c) visually distinct from any VCODE  (VC… vs CG-…)
--   SECURITY DEFINER, service-role/RPC-only (EXECUTE revoked from clients).
--
-- Validation (run after apply):
--   V1  SELECT public.fn_generate_cgcode_for_account('<account uuid>');  -- 'CG-…'
--   V2  -- two concurrent calls for one account return distinct codes
-- ============================================================

-- ── Disjoint per-prefix sequence store (NOT vcode_sequences) ──
CREATE TABLE IF NOT EXISTS public.cgcode_sequences (
  prefix     text        NOT NULL,
  last_seq   integer     NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cgcode_sequences_pkey PRIMARY KEY (prefix)
);

COMMENT ON TABLE public.cgcode_sequences IS
  'Per-prefix monotonic counter for CGCODE minting. DISJOINT from '
  'vcode_sequences — the roving namespace must stay independent of VCODE.';

ALTER TABLE public.cgcode_sequences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cgcode_sequences FROM authenticated;
REVOKE ALL ON public.cgcode_sequences FROM anon;

-- ── The minter ────────────────────────────────────────────────
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
  --   e.g. CG-AG1-0001. The CG- prefix is mandatory (RA1 CHECK) and
  --   visually disjoint from the VCODE family (VC…).
  v_prefix := 'CG-' || v_account_initial || upper(trim(v_group_code));

  INSERT INTO public.cgcode_sequences (prefix, last_seq, updated_at)
  VALUES (v_prefix, 1, now())
  ON CONFLICT (prefix) DO UPDATE
    SET last_seq   = public.cgcode_sequences.last_seq + 1,
        updated_at = now()
  RETURNING last_seq INTO v_next_seq;

  v_cgcode := v_prefix || '-' || lpad(v_next_seq::text, 4, '0');

  -- Recheck against live ACTIVE coverage codes for this account
  -- (partial unique allows archived-code reuse, so scope the probe).
  WHILE EXISTS (
    SELECT 1 FROM public.coverage_groups
    WHERE account_id = p_account_id
      AND coverage_code = v_cgcode
      AND archived_at IS NULL
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
  'Mints a CG-prefixed coverage code unique per active account. Disjoint '
  'from the VCODE minter (own cgcode_sequences store). SECURITY DEFINER, '
  'service-role/RPC-only.';

REVOKE ALL ON FUNCTION public.fn_generate_cgcode_for_account(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_generate_cgcode_for_account(uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.fn_generate_cgcode_for_account(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_generate_cgcode_for_account(uuid) TO service_role;
