-- Migration: 20262606000210_manage_account_positions_rpc.sql
-- Description: Provide manage_account_position and get_account_positions_detailed RPCs for Data Team to govern account positions

-- 1. Detailed Account Positions listing with active employee & vacancy usage counts
CREATE OR REPLACE FUNCTION public.get_account_positions_detailed(p_account_id uuid)
RETURNS TABLE(
  position_id uuid,
  position_name text,
  position_code text,
  is_active boolean,
  mapped_at timestamp with time zone,
  active_employee_count bigint,
  open_vacancy_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS position_id,
    p.position_name,
    p.position_code,
    COALESCE(ap.is_active, true) AS is_active,
    ap.created_at AS mapped_at,
    (
      SELECT count(*)
      FROM public.plantilla pl
      WHERE pl.account_id = p_account_id
        AND (pl.position_id = p.id OR LOWER(TRIM(pl.position)) = LOWER(TRIM(p.position_name)))
        AND pl.status NOT IN ('Inactive', 'Deactivated')
    ) AS active_employee_count,
    (
      SELECT count(*)
      FROM public.vacancies v
      WHERE v.account_id = p_account_id
        AND (v.position_id = p.id OR LOWER(TRIM(v.position)) = LOWER(TRIM(p.position_name)))
        AND v.status = 'Open'
        AND v.is_archived = false
    ) AS open_vacancy_count
  FROM public.account_positions ap
  JOIN public.positions p ON p.id = ap.position_id
  WHERE ap.account_id = p_account_id
  ORDER BY p.position_name ASC;
END;
$function$;

-- 2. Atomic Account Position Management RPC (link, create_and_link, unlink)
CREATE OR REPLACE FUNCTION public.manage_account_position(
  p_action text,
  p_account_id uuid,
  p_position_id uuid DEFAULT NULL,
  p_position_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_role_level int;
  v_account_name text;
  v_pos_id uuid;
  v_pos_name text;
  v_formatted_name text;
  v_active_pl_count bigint;
  v_open_vac_count bigint;
BEGIN
  -- RBAC Gate: Only Data Team and Super Admin (role level >= 30: Encoder 30, Head Admin 90, Super Admin 100)
  v_role_level := COALESCE(public.get_my_role_level(), 0);
  IF v_role_level < 30 THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only Data Team and Super Admin can manage account positions (role level >= 30 required). Current level: %', v_role_level;
  END IF;

  -- Validate Account
  IF p_account_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_ARGUMENT: p_account_id is required.';
  END IF;

  SELECT account_name INTO v_account_name
  FROM public.accounts
  WHERE id = p_account_id;

  IF v_account_name IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND: Account with id % does not exist.', p_account_id;
  END IF;

  -- Action 1: LINK an existing master position to the account
  IF p_action = 'link' THEN
    IF p_position_id IS NULL THEN
      RAISE EXCEPTION 'INVALID_ARGUMENT: p_position_id is required for action "link".';
    END IF;

    SELECT id, position_name INTO v_pos_id, v_pos_name
    FROM public.positions
    WHERE id = p_position_id;

    IF v_pos_id IS NULL THEN
      RAISE EXCEPTION 'NOT_FOUND: Position with id % does not exist.', p_position_id;
    END IF;

    INSERT INTO public.account_positions (account_id, position_id, is_active, updated_at)
    VALUES (p_account_id, v_pos_id, true, now())
    ON CONFLICT (account_id, position_id)
    DO UPDATE SET is_active = true, updated_at = now();

    -- Audit log
    BEGIN
      PERFORM public.log_audit_event(
        'account_positions',
        'LINK',
        v_pos_id,
        NULL,
        jsonb_build_object(
          'account_id', p_account_id,
          'account_name', v_account_name,
          'position_id', v_pos_id,
          'position_name', v_pos_name
        )
      );
    EXCEPTION WHEN OTHERS THEN
      -- Safe audit log fallback
      NULL;
    END;

    RETURN jsonb_build_object(
      'success', true,
      'action', 'link',
      'account_id', p_account_id,
      'account_name', v_account_name,
      'position_id', v_pos_id,
      'position_name', v_pos_name,
      'message', format('Position "%s" successfully linked to account "%s".', v_pos_name, v_account_name)
    );

  -- Action 2: CREATE a new master position (properly formatted) and LINK to account
  ELSIF p_action = 'create_and_link' THEN
    IF p_position_name IS NULL OR length(trim(p_position_name)) < 2 THEN
      RAISE EXCEPTION 'INVALID_ARGUMENT: p_position_name must be at least 2 characters.';
    END IF;

    -- Apply canonical Title Case and 2-3 letter acronym uppercase rule
    v_formatted_name := public.fn_format_position_title(trim(p_position_name));

    -- Check if position already exists in master catalog
    SELECT id, position_name INTO v_pos_id, v_pos_name
    FROM public.positions
    WHERE lower(trim(position_name)) = lower(trim(v_formatted_name))
    LIMIT 1;

    IF v_pos_id IS NULL THEN
      -- Create new master position
      INSERT INTO public.positions (position_name, is_active)
      VALUES (v_formatted_name, true)
      RETURNING id, position_name INTO v_pos_id, v_pos_name;

      BEGIN
        PERFORM public.log_audit_event(
          'positions',
          'INSERT',
          v_pos_id,
          NULL,
          jsonb_build_object('position_name', v_pos_name)
        );
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END IF;

    -- Link to account
    INSERT INTO public.account_positions (account_id, position_id, is_active, updated_at)
    VALUES (p_account_id, v_pos_id, true, now())
    ON CONFLICT (account_id, position_id)
    DO UPDATE SET is_active = true, updated_at = now();

    -- Audit log
    BEGIN
      PERFORM public.log_audit_event(
        'account_positions',
        'LINK',
        v_pos_id,
        NULL,
        jsonb_build_object(
          'account_id', p_account_id,
          'account_name', v_account_name,
          'position_id', v_pos_id,
          'position_name', v_pos_name
        )
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    RETURN jsonb_build_object(
      'success', true,
      'action', 'create_and_link',
      'account_id', p_account_id,
      'account_name', v_account_name,
      'position_id', v_pos_id,
      'position_name', v_pos_name,
      'message', format('Position "%s" created and linked to account "%s".', v_pos_name, v_account_name)
    );

  -- Action 3: UNLINK a position from the account (with in-use protection)
  ELSIF p_action = 'unlink' THEN
    IF p_position_id IS NULL THEN
      RAISE EXCEPTION 'INVALID_ARGUMENT: p_position_id is required for action "unlink".';
    END IF;

    SELECT id, position_name INTO v_pos_id, v_pos_name
    FROM public.positions
    WHERE id = p_position_id;

    IF v_pos_id IS NULL THEN
      RAISE EXCEPTION 'NOT_FOUND: Position with id % does not exist.', p_position_id;
    END IF;

    -- Check active employee count
    SELECT count(*) INTO v_active_pl_count
    FROM public.plantilla pl
    WHERE pl.account_id = p_account_id
      AND (pl.position_id = v_pos_id OR lower(trim(pl.position)) = lower(trim(v_pos_name)))
      AND pl.status NOT IN ('Inactive', 'Deactivated');

    -- Check open vacancy count
    SELECT count(*) INTO v_open_vac_count
    FROM public.vacancies v
    WHERE v.account_id = p_account_id
      AND (v.position_id = v_pos_id OR lower(trim(v.position)) = lower(trim(v_pos_name)))
      AND v.status = 'Open'
      AND v.is_archived = false;

    IF (v_active_pl_count + v_open_vac_count) > 0 THEN
      RAISE EXCEPTION 'CANNOT_UNLINK: Position "%" cannot be unlinked from account "%" because % active employee(s) and % open vacancy(ies) are currently assigned to it.',
        v_pos_name, v_account_name, v_active_pl_count, v_open_vac_count;
    END IF;

    -- Safe to delete the link
    DELETE FROM public.account_positions
    WHERE account_id = p_account_id AND position_id = v_pos_id;

    -- Audit log
    BEGIN
      PERFORM public.log_audit_event(
        'account_positions',
        'UNLINK',
        v_pos_id,
        jsonb_build_object(
          'account_id', p_account_id,
          'account_name', v_account_name,
          'position_id', v_pos_id,
          'position_name', v_pos_name
        ),
        NULL
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    RETURN jsonb_build_object(
      'success', true,
      'action', 'unlink',
      'account_id', p_account_id,
      'account_name', v_account_name,
      'position_id', v_pos_id,
      'position_name', v_pos_name,
      'message', format('Position "%s" unlinked from account "%s".', v_pos_name, v_account_name)
    );

  ELSE
    RAISE EXCEPTION 'INVALID_ACTION: Unknown action "%". Valid actions: link, create_and_link, unlink.', p_action;
  END IF;
END;
$function$;

-- 3. Grants
GRANT EXECUTE ON FUNCTION public.get_account_positions_detailed(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.manage_account_position(text, uuid, uuid, text) TO authenticated;
