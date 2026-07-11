-- ============================================================
-- ohm#f4k9p2q9: Allow 'Floating' in plantilla_separation_status_check
-- Migration: 20261219000001_allow_floating_separation_status.sql
-- ============================================================
-- Root cause: plantilla_separation_status_check only allows
--   'AWOL', 'Resigned', 'Endo', 'Others'.
-- set_plantilla_floating (20261007000001) writes separation_status = 'Floating'
-- but the constraint never included 'Floating', causing the RPC to fail.
--
-- Fix: extend the constraint to include 'Floating'.
-- All previously allowed values are preserved.
-- NOT VALID: no full table scan on the live DB (no existing rows have
-- separation_status = 'Floating' because the constraint blocked them).
-- VALIDATE is run immediately after to make the constraint fully enforced.
-- ============================================================

-- §1  Drop existing constraint
ALTER TABLE public.plantilla
  DROP CONSTRAINT IF EXISTS plantilla_separation_status_check;

-- §2  Recreate with 'Floating' added
ALTER TABLE public.plantilla
  ADD CONSTRAINT plantilla_separation_status_check
  CHECK (separation_status = ANY (ARRAY[
    'AWOL'::text,
    'Resigned'::text,
    'Endo'::text,
    'Others'::text,
    'Floating'::text
  ])) NOT VALID;

-- §3  Validate (safe — no existing rows violate; runs as a metadata-only pass)
ALTER TABLE public.plantilla
  VALIDATE CONSTRAINT plantilla_separation_status_check;

-- ============================================================
-- Rollback (run to revert):
--
-- ALTER TABLE public.plantilla
--   DROP CONSTRAINT IF EXISTS plantilla_separation_status_check;
--
-- ALTER TABLE public.plantilla
--   ADD CONSTRAINT plantilla_separation_status_check
--   CHECK (separation_status = ANY (ARRAY[
--     'AWOL'::text,
--     'Resigned'::text,
--     'Endo'::text,
--     'Others'::text
--   ])) NOT VALID;
--
-- ALTER TABLE public.plantilla
--   VALIDATE CONSTRAINT plantilla_separation_status_check;
-- ============================================================
