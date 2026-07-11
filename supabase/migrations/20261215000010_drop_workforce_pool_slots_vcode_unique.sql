-- Migration: 20261215000010_drop_workforce_pool_slots_vcode_unique.sql
-- Goal: Allow multiple workforce_pool_slots rows to share the same vcode.
--
-- Root cause: workforce_pool_slots_vcode_key was a UNIQUE index on vcode,
-- originally built for the old architecture (1 HC = 1 VCode = 1 slot).
-- The new architecture (ohm#p9x4k7m2 migration 009) creates N slot rows
-- per request all sharing one VCode (e.g. HC=13 → 13 slots, same vcode).
-- The UNIQUE constraint blocks the 2nd INSERT with:
--   "duplicate key value violates unique constraint workforce_pool_slots_vcode_key"
--
-- Fix:
-- - Drop the unique index/constraint on workforce_pool_slots.vcode.
-- - Row uniqueness is preserved by the primary key on workforce_pool_slots.id.
-- - VCode uniqueness across requests is still enforced by vacancies.vcode UNIQUE.
-- - No slot data is deleted or modified.

ALTER TABLE public.workforce_pool_slots
  DROP CONSTRAINT IF EXISTS workforce_pool_slots_vcode_key;

DROP INDEX IF EXISTS public.workforce_pool_slots_vcode_key;
