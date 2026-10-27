-- ============================================================
-- ohm#plan05: Allow 'Terminated' and 'End of Contract' in plantilla_separation_status_check
-- Migration: 20261027150000_allow_terminated_separation_status.sql
-- ============================================================
-- Root cause: plantilla_separation_status_check only allows
--   'AWOL', 'Resigned', 'Endo', 'Others', 'Floating'.
-- plantilla_update_separation allows 'Terminated' and 'End of Contract',
-- but the constraint never included them, which would cause an attempt to
-- separate an employee with status 'Terminated' to fail with SQLSTATE 23514.
--
-- Fix: extend the constraint to include 'Terminated' and 'End of Contract'.
-- All previously allowed values are preserved.
-- NOT VALID: avoids full table scan / table locks on live DB.
-- VALIDATE is run immediately after.
-- ============================================================

-- §1  Drop existing constraint
ALTER TABLE public.plantilla
  DROP CONSTRAINT IF EXISTS plantilla_separation_status_check;

-- §2  Recreate with 'Terminated' and 'End of Contract' added
ALTER TABLE public.plantilla
  ADD CONSTRAINT plantilla_separation_status_check
  CHECK (separation_status = ANY (ARRAY[
    'AWOL'::text,
    'Resigned'::text,
    'Endo'::text,
    'End of Contract'::text,
    'Terminated'::text,
    'Others'::text,
    'Floating'::text
  ])) NOT VALID;

-- §3  Validate constraint
ALTER TABLE public.plantilla
  VALIDATE CONSTRAINT plantilla_separation_status_check;
