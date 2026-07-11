-- ============================================================
-- OHM2026_0065 — Fix generate_vcode_for_account: account_code fallback
-- Migration: 20260831000000_fix_vcode_generation_account_code_fallback.sql
-- ============================================================
-- ROOT CAUSE:
--   generate_vcode_for_account (rewritten in 20260602000003) requires
--   accounts.account_code to be non-null. 107 of ~109 accounts have
--   account_code = NULL, so VCODE creation fails for almost every account:
--     "account_code not set for account_id: <id>"
--
-- REPRODUCTION:
--   HC request HC-416CCEEF for account MORE (id 4eac2236-...) → Create VCODE
--   → create_plantilla_slot_from_request → generate_vcode_for_account
--   → RAISE EXCEPTION 'account_code not set ...'  (uncaught, surfaces to UI)
--
-- FIX STRATEGY (additive, no data mutation):
--   When account_code IS SET (non-null, non-empty):
--     Use new format:  {account_code}-{group_code}-XXXX  (separator '-')
--     Example:         BK-G1-0001
--   When account_code IS NULL or empty:
--     Fall back to legacy format: VC{initial}{group_code}_XXXX  (separator '_')
--     Example:         VCMG2_0008  (exactly matches existing VCODEs for MORE)
--
--   The vcode_sequences table already has rows for legacy prefixes (e.g. VCMG2).
--   The ON CONFLICT ... DO UPDATE clause advances the existing sequence; new
--   VCODEs resume from where they left off. No gap or collision is introduced.
--
--   The collision guard continues to check ALL vacancies rows (including
--   is_archived=true and soft-deleted rows), consistent with 20260602000003.
--
-- SCOPE:
--   • Replaces only generate_vcode_for_account — no other function is changed.
--   • No table DDL, no data backfill, no RLS change.
--   • Idempotent: safe to re-apply.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.generate_vcode_for_account(p_account_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_account_name  text;
  v_account_code  text;
  v_group_code    text;
  v_initial       text;
  v_prefix        text;
  v_separator     text;
  v_next_seq      integer;
  v_vcode         text;
BEGIN
  SELECT a.account_name, a.account_code, g.group_code
  INTO   v_account_name, v_account_code, v_group_code
  FROM   public.accounts a
  JOIN   public.groups   g ON g.id = a.group_id
  WHERE  a.id = p_account_id;

  IF v_account_name IS NULL THEN
    RAISE EXCEPTION 'account not found for account_id: %', p_account_id;
  END IF;

  IF NULLIF(TRIM(COALESCE(v_group_code, '')), '') IS NULL THEN
    RAISE EXCEPTION 'group_code not set for account_id: %', p_account_id;
  END IF;

  IF v_account_code IS NOT NULL AND TRIM(v_account_code) <> '' THEN
    -- ── New format (account_code is set) ────────────────────────────────────
    -- Format: {account_code}-{group_code}-XXXX
    -- Example: BK-G1-0001
    v_prefix    := TRIM(v_account_code) || '-' || UPPER(TRIM(v_group_code));
    v_separator := '-';
  ELSE
    -- ── Legacy fallback (account_code not set) ───────────────────────────────
    -- Format: VC{initial}{group_code}_XXXX  (original OHMployee format)
    -- Example: VCMG2_0008
    -- Preserves all existing VCODE sequences for un-coded accounts.
    v_initial := UPPER(LEFT(REGEXP_REPLACE(TRIM(v_account_name), '[^A-Za-z0-9]', '', 'g'), 1));
    IF NULLIF(v_initial, '') IS NULL THEN
      RAISE EXCEPTION 'account initial could not be generated for account_id: %', p_account_id;
    END IF;
    v_prefix    := 'VC' || v_initial || UPPER(TRIM(v_group_code));
    v_separator := '_';
  END IF;

  -- Atomically advance (or initialise) the sequence for this prefix.
  INSERT INTO public.vcode_sequences (prefix, last_seq, updated_at)
  VALUES (v_prefix, 1, NOW())
  ON CONFLICT (prefix) DO UPDATE
    SET last_seq   = public.vcode_sequences.last_seq + 1,
        updated_at = NOW()
  RETURNING last_seq INTO v_next_seq;

  v_vcode := v_prefix || v_separator || LPAD(v_next_seq::text, 4, '0');

  -- Collision guard — intentionally checks ALL rows including archived rows
  -- (no is_archived filter). Archived VCODEs must never be reused.
  -- vacancies_vcode_key UNIQUE (unconditional) is the final safety net.
  WHILE EXISTS (SELECT 1 FROM public.vacancies WHERE vcode = v_vcode) LOOP
    UPDATE public.vcode_sequences
    SET last_seq   = last_seq + 1,
        updated_at = NOW()
    WHERE prefix = v_prefix
    RETURNING last_seq INTO v_next_seq;
    v_vcode := v_prefix || v_separator || LPAD(v_next_seq::text, 4, '0');
  END LOOP;

  RETURN v_vcode;
END;
$$;

COMMENT ON FUNCTION public.generate_vcode_for_account(uuid) IS
  'Generates a globally unique VCODE for an account. '
  'When accounts.account_code IS SET: format is {account_code}-{group_code}-XXXX (new format, e.g. BK-G1-0001). '
  'When accounts.account_code IS NULL: falls back to legacy format VC{initial}{group_code}_XXXX (e.g. VCMG2_0008), '
  'preserving existing sequences for accounts that have not yet been assigned a code. '
  'Collision guard checks ALL rows in vacancies (including is_archived=true) so archived VCODEs are never reused. '
  'vacancies_vcode_key UNIQUE (unconditional) is the secondary safety net. '
  'OHM2026_0065: restored account_code-null fallback; no data migration required.';

COMMIT;
