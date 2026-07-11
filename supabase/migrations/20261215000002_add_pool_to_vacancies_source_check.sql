-- =============================================================================
-- Migration: 20261215000002_add_pool_to_vacancies_source_check.sql
-- Fix: create_pool_vacancy RPC inserts source = 'pool' but vacancies_source_check
-- only allows ('hc_request', 'plantilla', 'manual'). Add 'pool' to the allowed set.
-- =============================================================================

ALTER TABLE public.vacancies DROP CONSTRAINT IF EXISTS vacancies_source_check;
ALTER TABLE public.vacancies
  ADD CONSTRAINT vacancies_source_check
  CHECK ((source = ANY (ARRAY['hc_request'::text, 'plantilla'::text, 'manual'::text, 'pool'::text])));
