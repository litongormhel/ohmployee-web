-- Fix Global Search runtime failure caused by PL/pgSQL output parameter
-- names conflicting with CTE column names inside search_global_index.
--
-- Rebuild the existing function with PostgreSQL's variable conflict resolver
-- set to prefer SQL column names. Local variables in this function already use
-- the v_* prefix, so this targets the result TABLE column ambiguity without
-- changing search predicates, RBAC, RLS, or result shape.

DO $$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef('public.search_global_index(text, integer)'::regprocedure)
  INTO v_definition;

  IF v_definition IS NULL THEN
    RETURN;
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
