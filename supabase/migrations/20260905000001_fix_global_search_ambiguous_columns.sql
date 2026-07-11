-- Fix Global Search runtime failure caused by PL/pgSQL output parameter
-- names conflicting with CTE column names inside search_global_index.
--
-- This file is intentionally ordered after the current root migration tail so
-- fresh database replays run it after the original Global Search RPC exists.

DO $$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef('public.search_global_index(text, integer)'::regprocedure)
  INTO v_definition;

  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'search_global_index(text, integer) does not exist';
  END IF;

  IF position('#variable_conflict use_column' IN v_definition) = 0 THEN
    v_definition := replace(
      v_definition,
      'AS $function$' || chr(10) || 'DECLARE',
      'AS $function$' || chr(10) || '#variable_conflict use_column' || chr(10) || 'DECLARE'
    );

    EXECUTE v_definition;
  END IF;
END;
$$;
