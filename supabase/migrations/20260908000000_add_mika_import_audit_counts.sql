-- Migration: 20260908000000_add_mika_import_audit_counts.sql
-- Ticket: MIKA Import Checker Audit Counts
--
-- Description:
--   Add matched_count, ghost_count, blocked_count, and skipped_count to mika_import_logs.
--   These columns capture the detailed audit counts for checker-only imports.

ALTER TABLE public.mika_import_logs
ADD COLUMN IF NOT EXISTS matched_count integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS ghost_count integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS blocked_count integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS skipped_count integer DEFAULT 0;

COMMENT ON COLUMN public.mika_import_logs.matched_count IS 'Checker-only: count of employee rows matching active Plantilla records with updates.';
COMMENT ON COLUMN public.mika_import_logs.ghost_count IS 'Checker-only: count of employee rows flagged as possible ghost employees (not in Plantilla).';
COMMENT ON COLUMN public.mika_import_logs.blocked_count IS 'Checker-only: count of employee rows blocked due to format or validation errors.';
COMMENT ON COLUMN public.mika_import_logs.skipped_count IS 'Checker-only: count of employee rows skipped due to no meaningful changes.';
