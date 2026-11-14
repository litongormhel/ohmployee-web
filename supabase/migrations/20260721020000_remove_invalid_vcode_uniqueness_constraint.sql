-- ============================================================================
-- OHM2026_0086 — Remove Invalid VCODE Uniqueness Constraint and Align Plantilla to Slot-Based Model
-- Migration: 20260721020000_remove_invalid_vcode_uniqueness_constraint.sql
-- Prompt ID: ohm#c81d4p9x
-- ============================================================================
--
-- Objective:
--   1. Drop invalid unique index `uq_plantilla_vcode_active_occupied` on public.plantilla(vcode)
--      which erroneously enforced 1 VCODE = 1 active employee, blocking multi-headcount allocation.
--   2. Ensure slot-level integrity per ADR-001 by validating slot-occupant uniqueness
--      on public.plantilla_slots (current_occupant_plantilla_id).
--
-- Domain Invariant (ADR-001):
--   1 VCODE = N slots (HC)
--   1 slot = 1 employee
--   COUNT(active plantilla rows per slot_id) <= 1
--   COUNT(active plantilla rows per vcode) <= HC
-- ============================================================================

BEGIN;

-- ============================================================================
-- §1 Drop Invalid VCODE-Level Uniqueness Constraint
-- ============================================================================

DROP INDEX IF EXISTS public.uq_plantilla_vcode_active_occupied;

-- ============================================================================
-- §2 Enforce Slot-Level Active Occupant Uniqueness
-- ============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_plantilla_slots_active_occupant
  ON public.plantilla_slots (current_occupant_plantilla_id)
  WHERE current_occupant_plantilla_id IS NOT NULL
    AND slot_status IN ('occupied', 'filled');

COMMENT ON INDEX public.uq_plantilla_slots_active_occupant IS
  'Enforces ADR-001 slot-level integrity: each active plantilla employee can occupy at most 1 slot.';

COMMIT;
