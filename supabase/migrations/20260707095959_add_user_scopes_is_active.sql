-- Migration: 20260707100002b_add_user_scopes_is_active
-- Created: 2026-07-07
-- Prompt: ohm#5d1e7c9b (Fix Migration Failure — Enforce user_scopes.is_active Schema Alignment)
-- Dependency: MUST run BEFORE 20260707100003_hrco_validation_enforce_active_scope.sql
--
-- Purpose:
--   Add the is_active column to public.user_scopes so that the W4 pre-flight
--   guard in migration 20260707100003 passes on environments (staging, prod)
--   where the column was never added via a prior migration.
--
-- Safety:
--   • ADD COLUMN IF NOT EXISTS — fully idempotent; safe to run multiple times.
--   • DEFAULT true — all existing scope rows become active (preserves current
--     behavior: no existing user loses scope access).
--   • NOT NULL — enforces the intended invariant; no data is mutated.
--   • No table drop/recreate. No RLS changes. No grant changes.
--   • No other columns touched.
--
-- Execution order (local timestamp sort):
--   20260707100000_hrco_scope_isolation_plantilla.sql        (applied)
--   20260707100001_hrco_email_import_validation.sql          (applied)
--   20260707100002_get_plantilla_needs_hrco_employees.sql    (applied)
--   20260707100002b_add_user_scopes_is_active.sql            ← THIS FILE
--   20260707100003_hrco_validation_enforce_active_scope.sql  (depends on is_active)

BEGIN;

ALTER TABLE public.user_scopes
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

COMMIT;
