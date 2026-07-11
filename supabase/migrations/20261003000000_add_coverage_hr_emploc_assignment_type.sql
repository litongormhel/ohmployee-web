-- ============================================================
-- OHM2026_0087A_FIX1 — HR Emploc Coverage assignment enum
-- Migration: 20261003000000_add_coverage_hr_emploc_assignment_type.sql
-- ============================================================
-- Coverage Group onboarding is slot-first and does not use legacy
-- roving_assignments. Add a dedicated assignment type before replacing the
-- HR Emploc constraint/RPC in the next migration.

ALTER TYPE public.hr_emploc_assignment_type ADD VALUE IF NOT EXISTS 'Coverage';
