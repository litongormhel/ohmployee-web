-- Preserve the Global Search RPC response contract after resolving PL/pgSQL
-- output-parameter ambiguity by explicitly naming the UNION CTE columns.

DO $$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef('public.search_global_index(text, integer)'::regprocedure)
  INTO v_definition;

  IF v_definition IS NULL THEN
    RETURN;
  END IF;

  IF position('combined(result_type, record_id, primary_label' IN v_definition) = 0 THEN
    v_definition := replace(
      v_definition,
      'combined AS (',
      'combined(result_type, record_id, primary_label, secondary_label, status, matched_field, group_name, account_name, created_at, navigation_target, navigation_id, priority) AS ('
    );

    EXECUTE v_definition;
  END IF;
END;
$$;
