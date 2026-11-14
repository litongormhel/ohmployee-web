-- vacancy_requests is confirmed dead (7 rows, last insert 2026-05-09, UI form removed
-- per Ohm's architecture decision — all vacancies must originate from Plantilla except
-- Import Vacancy). DELETE and UPDATE were already blocked (qual=false); this completes
-- the lockdown by blocking INSERT the same way, removing the accidental ops+encoder
-- widening that had been picked up from a staging-only policy during ohm#7n3wk8qm.

DROP POLICY IF EXISTS vreq_insert_ops_or_encoder ON public.vacancy_requests;
DROP POLICY IF EXISTS vreq_insert_ops_scoped ON public.vacancy_requests;
DROP POLICY IF EXISTS vreq_insert_blocked ON public.vacancy_requests;

CREATE POLICY vreq_insert_blocked ON public.vacancy_requests
FOR INSERT
TO authenticated
WITH CHECK (false);
