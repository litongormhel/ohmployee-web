-- Migration: 20262606000100_grant_list_web_vacancies_postgres.sql
-- Description: Grant execute on list_web_vacancies to postgres role for CLI administration and query capability.

BEGIN;

GRANT EXECUTE ON FUNCTION public.list_web_vacancies(text, uuid, uuid, text, text, text, text, date, date, integer, integer, text, text) TO postgres;

COMMIT;
