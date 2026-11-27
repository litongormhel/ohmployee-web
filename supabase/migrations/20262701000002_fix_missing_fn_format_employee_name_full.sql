-- Fix missing public.fn_format_employee_name_full(text, text, text) referenced by move_to_plantilla
-- Formats employee name as: LASTNAME, FIRSTNAME MIDDLENAME (uppercase, trimmed)

CREATE OR REPLACE FUNCTION public.fn_format_employee_name_full(
  p_last_name text,
  p_first_name text,
  p_middle_name text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $$
DECLARE
  v_last   text := NULLIF(upper(trim(coalesce(p_last_name, ''))), '');
  v_first  text := NULLIF(upper(trim(coalesce(p_first_name, ''))), '');
  v_middle text := NULLIF(upper(trim(coalesce(p_middle_name, ''))), '');
  v_given  text;
BEGIN
  v_given := trim(concat_ws(' ', v_first, v_middle));
  IF v_last IS NOT NULL AND v_given <> '' THEN
    RETURN v_last || ', ' || v_given;
  ELSIF v_last IS NOT NULL THEN
    RETURN v_last;
  ELSIF v_given <> '' THEN
    RETURN v_given;
  ELSE
    RETURN '';
  END IF;
END;
$$;
