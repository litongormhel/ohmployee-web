-- Migration: 20261219000004_drop_reject_amr_overload.sql
-- Description: Drop the obsolete 3-argument overload of reject_applicant_movement_request
--   to resolve call ambiguity for the 2-argument version.

DROP FUNCTION IF EXISTS public.reject_applicant_movement_request(uuid, text, text);
