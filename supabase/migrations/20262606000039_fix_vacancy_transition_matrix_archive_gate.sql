-- Migration: 20262606000039_fix_vacancy_transition_matrix_archive_gate
-- Created: 2026-08-10 (filename version stamped 20262606000039 to sort after this repo's
-- pre-existing non-chronological remote-latest 20262606000038 -- required by `supabase db push`'s
-- strict ordering; the filename quirk predates this task and is not otherwise touched)
-- Purpose: Add an additive WHEN branch to fn_is_valid_vacancy_transition() admitting X->Archived
--          from every live status, so the SA-gated archive writers (archive_vacancy_record,
--          fn_archive_all_operational_data, fn_qa_archive_operational_data_reset,
--          fn_archive_vacancy_data, fn_archive_moses_hq_data, fn_archive_hired_vacancies) are no
--          longer blocked by trg_enforce_vacancy_transition on staging.
--
-- Smoke Tests:
-- S1: SELECT fn_is_valid_vacancy_transition('Open', 'Archived');       -- expect TRUE (was FALSE)
-- S2: SELECT fn_is_valid_vacancy_transition('Filled', 'Archived');     -- expect TRUE (was FALSE)
-- S3: SELECT fn_is_valid_vacancy_transition('Closed', 'Open');         -- expect FALSE (unchanged, out of scope ohm#9v3k7wmq)
-- S4: SELECT fn_is_valid_vacancy_transition('Draft', 'Closed');        -- expect TRUE (unchanged, pre-existing branch)
-- S5: In a ROLLBACK-wrapped transaction, call archive_vacancy_record() on a live Open/Filled
--     vacancy and confirm it no longer raises "Invalid vacancy status transition".

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_is_valid_vacancy_transition(p_old text, p_new text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    -- NULL/blank old (insert path) → only Draft / Pending Approval / Open allowed at create time
    WHEN p_old IS NULL OR p_old = '' THEN p_new IN ('Draft','Pending Approval','Open')
    WHEN p_old = p_new THEN TRUE
    WHEN p_old = 'Draft'            AND p_new IN ('Pending Approval','Closed','Rejected') THEN TRUE
    WHEN p_old = 'Pending Approval' AND p_new IN ('Open','Rejected','Closed')             THEN TRUE
    WHEN p_old = 'Open'             AND p_new IN ('On Hold','Filled','Closed')             THEN TRUE
    WHEN p_old = 'On Hold'          AND p_new IN ('Open','Closed')                         THEN TRUE
    -- Filled → Open / Closed: allowed for Coverage Group / Slot Closure transitions.
    WHEN p_old = 'Filled'           AND p_new IN ('Open','Closed')                         THEN TRUE
    -- Legacy values: allow same-state and migration to canon.
    WHEN p_old IN ('For Sourcing','Backout') AND p_new IN ('Open','Closed','Filled','On Hold') THEN TRUE
    WHEN p_old = 'Archived'         AND p_new = 'Archived'                                  THEN TRUE
    -- Archive from any live status: matches the SA-gated bulk/manual archive writers
    -- (archive_vacancy_record, fn_archive_all_operational_data,
    -- fn_qa_archive_operational_data_reset, fn_archive_vacancy_data,
    -- fn_archive_moses_hq_data, fn_archive_hired_vacancies), none of which restrict OLD.status.
    -- ohm#3k8n5wqz (2026-08-10).
    WHEN p_new = 'Archived' THEN TRUE
    ELSE FALSE
  END;
$function$;

COMMIT;
