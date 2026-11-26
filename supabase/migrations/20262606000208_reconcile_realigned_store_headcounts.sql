-- Migration: 20262606000208_reconcile_realigned_store_headcounts.sql
-- Created: 2026-11-26T14:23:20.370Z
-- Description: reconcile realigned store headcounts

BEGIN;

-- Reconcile required_headcount to match total active capacity slots (occupied + open + pipeline)
UPDATE public.vacancies
SET required_headcount = 3.0000
WHERE vcode = 'VBFG5_0009';

UPDATE public.vacancies
SET required_headcount = 2.0000
WHERE vcode = 'VCBPIG1_0252';

UPDATE public.vacancies
SET required_headcount = 2.0000
WHERE vcode = 'CPSEJV16';

COMMIT;
