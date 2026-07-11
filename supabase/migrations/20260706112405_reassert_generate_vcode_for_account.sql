CREATE OR REPLACE FUNCTION public.generate_vcode_for_account(p_account_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_account_name  text;
  v_account_code  text;
  v_group_code    text;
  v_initial       text;
  v_prefix        text;
  v_separator     text;
  v_next_seq      integer;
  v_vcode         text;
BEGIN
  SELECT a.account_name, a.account_code, g.group_code
  INTO   v_account_name, v_account_code, v_group_code
  FROM   public.accounts a
  JOIN   public.groups   g ON g.id = a.group_id
  WHERE  a.id = p_account_id;

  IF v_account_name IS NULL THEN
    RAISE EXCEPTION 'account not found for account_id: %', p_account_id;
  END IF;

  IF NULLIF(TRIM(COALESCE(v_group_code, '')), '') IS NULL THEN
    RAISE EXCEPTION 'group_code not set for account_id: %', p_account_id;
  END IF;

  IF v_account_code IS NOT NULL AND TRIM(v_account_code) <> '' THEN
    v_prefix    := TRIM(v_account_code) || '-' || UPPER(TRIM(v_group_code));
    v_separator := '-';
  ELSE
    v_initial := UPPER(
      LEFT(
        REGEXP_REPLACE(TRIM(v_account_name), '[^A-Za-z0-9]', '', 'g'),
        1
      )
    );

    IF NULLIF(v_initial, '') IS NULL THEN
      RAISE EXCEPTION 'account initial could not be generated for account_id: %', p_account_id;
    END IF;

    v_prefix    := 'VC' || v_initial || UPPER(TRIM(v_group_code));
    v_separator := '_';
  END IF;

  INSERT INTO public.vcode_sequences (prefix, last_seq, updated_at)
  VALUES (v_prefix, 1, NOW())
  ON CONFLICT (prefix) DO UPDATE
    SET last_seq   = public.vcode_sequences.last_seq + 1,
        updated_at = NOW()
  RETURNING last_seq INTO v_next_seq;

  v_vcode := v_prefix || v_separator || LPAD(v_next_seq::text, 4, '0');

  WHILE EXISTS (
    SELECT 1 FROM public.vacancies WHERE vcode = v_vcode
  ) LOOP
    UPDATE public.vcode_sequences
    SET last_seq   = last_seq + 1,
        updated_at = NOW()
    WHERE prefix = v_prefix
    RETURNING last_seq INTO v_next_seq;

    v_vcode := v_prefix || v_separator || LPAD(v_next_seq::text, 4, '0');
  END LOOP;

  RETURN v_vcode;
END;
$$;

COMMENT ON FUNCTION public.generate_vcode_for_account(uuid) IS 'Generates globally unique VCODE with dual format support';

ALTER FUNCTION public.generate_vcode_for_account(uuid) OWNER TO postgres;