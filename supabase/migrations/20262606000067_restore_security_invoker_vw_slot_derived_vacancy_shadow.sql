-- ============================================================================
-- Migration: 20262606000067_restore_security_invoker_vw_slot_derived_vacancy_shadow.sql
-- Prompt ID: ohm#9q5n3wvx
-- Title: Restore security_invoker = true on vw_slot_derived_vacancy_shadow
--
-- Objectives:
--   1. Restore security_invoker = true on public.vw_slot_derived_vacancy_shadow
--      which was unintentionally dropped in migration 20262606000063 (ohm#w85m286a)
--      when CREATE OR REPLACE VIEW was executed without WITH (security_invoker = true).
--   2. Use ALTER VIEW ... SET (security_invoker = true) to avoid redefining the view
--      body, avoid touching existing grants (authenticated, service_role), and ensure
--      zero side effects on sibling views or underlying tables.
-- ============================================================================

ALTER VIEW public.vw_slot_derived_vacancy_shadow SET (security_invoker = true);
