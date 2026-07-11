-- =============================================================================
-- Migration: 20260604000004_payroll_review_center.sql
-- OHM2026_0074 — Payroll Review Center backend foundation
--
-- Establishes the persistent review/comment workflow for Import Payroll
-- checker findings. Import Payroll (OHM2026_0071/0072) remains read-only;
-- this module adds the Data Team → Ops communication and resolution layer.
--
-- Tables   : payroll_review_sessions, payroll_review_items
-- RPCs (7) : create_payroll_review_session, list_payroll_review_sessions,
--            list_payroll_review_items, list_ops_payroll_review_items,
--            submit_ops_payroll_review_comment, close_payroll_review_item,
--            close_payroll_review_session
-- RLS      : RPC-only writes; scoped SELECTs per role
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. payroll_review_sessions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payroll_review_sessions (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by        uuid,
  created_by_name   text,
  payroll_file_name text        NOT NULL,
  total_items       int         NOT NULL DEFAULT 0,
  status            text        NOT NULL DEFAULT 'Open',
  notes             text,
  closed_by         uuid,
  closed_by_name    text,
  closed_at         timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT payroll_review_sessions_status_check
    CHECK (status = ANY (ARRAY['Open', 'Closed']))
);

-- ---------------------------------------------------------------------------
-- 2. payroll_review_items
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payroll_review_items (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id            uuid        NOT NULL
    REFERENCES public.payroll_review_sessions(id) ON DELETE CASCADE,
  finding_type          text        NOT NULL,
  employee_number       text        NOT NULL,
  payroll_full_name     text,
  plantilla_full_name   text,
  payroll_account       text,
  payroll_group         text,
  plantilla_account     text,
  plantilla_group       text,
  assigned_account_id   uuid        NOT NULL
    REFERENCES public.accounts(id),
  assigned_group_id     uuid
    REFERENCES public.groups(id),
  status                text        NOT NULL DEFAULT 'Pending Ops Review',
  ops_response          text,
  ops_comment           text,
  commented_by          uuid,
  commented_by_name     text,
  commented_at          timestamptz,
  closed_by             uuid,
  closed_by_name        text,
  closed_at             timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT payroll_review_items_finding_type_check
    CHECK (finding_type = ANY (ARRAY[
      'Missing in Payroll',
      'Missing in Plantilla',
      'Paid Inactive',
      'Mismatch',
      'Duplicates'
    ])),

  CONSTRAINT payroll_review_items_status_check
    CHECK (status = ANY (ARRAY[
      'Pending Ops Review',
      'Ops Commented',
      'Needs Fixing',
      'Confirmed Correct',
      'Not My Scope',
      'Closed'
    ])),

  CONSTRAINT payroll_review_items_ops_response_check
    CHECK (ops_response IS NULL OR ops_response = ANY (ARRAY[
      'Correct as is',
      'Needs fixing',
      'Wrong account/group',
      'Employee inactive/resigned',
      'Employee transferred',
      'Not under my scope',
      'Other'
    ]))
);

-- ---------------------------------------------------------------------------
-- 3. Indexes
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_prc_items_session_id
  ON public.payroll_review_items (session_id);

CREATE INDEX IF NOT EXISTS idx_prc_items_status
  ON public.payroll_review_items (status);

CREATE INDEX IF NOT EXISTS idx_prc_items_assigned_account_id
  ON public.payroll_review_items (assigned_account_id);

CREATE INDEX IF NOT EXISTS idx_prc_items_employee_number
  ON public.payroll_review_items (employee_number);

CREATE INDEX IF NOT EXISTS idx_prc_sessions_status
  ON public.payroll_review_sessions (status);

CREATE INDEX IF NOT EXISTS idx_prc_sessions_created_at
  ON public.payroll_review_sessions (created_at DESC);

-- ---------------------------------------------------------------------------
-- 4. Row-Level Security
-- ---------------------------------------------------------------------------
ALTER TABLE public.payroll_review_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_review_items    ENABLE ROW LEVEL SECURITY;

-- Sessions: SA / HA / Encoder read-only (writes only through RPCs)
CREATE POLICY prc_sessions_select_mgmt
  ON public.payroll_review_sessions
  FOR SELECT
  TO authenticated
  USING (
    public.i_have_full_access()
    OR public.get_my_role_level() = 30
  );

-- Items: SA / HA / Encoder see all
CREATE POLICY prc_items_select_mgmt
  ON public.payroll_review_items
  FOR SELECT
  TO authenticated
  USING (
    public.i_have_full_access()
    OR public.get_my_role_level() = 30
  );

-- Items: OM sees only items assigned to their scoped accounts
CREATE POLICY prc_items_select_om_scoped
  ON public.payroll_review_items
  FOR SELECT
  TO authenticated
  USING (
    public.get_my_role_level() = 70
    AND assigned_account_id IN (
      -- group-scoped accounts (OM's standard scope)
      SELECT a.id
      FROM   public.accounts a
      JOIN   public.user_scopes us ON us.group_id = a.group_id
      WHERE  us.user_id     = public.get_my_profile_id()
        AND  a.is_active    = true
      UNION
      -- direct account-scoped entries
      SELECT us2.account_id
      FROM   public.user_scopes us2
      WHERE  us2.user_id    = public.get_my_profile_id()
        AND  us2.account_id IS NOT NULL
    )
  );

-- No direct INSERT / UPDATE / DELETE policies — all mutations via RPCs

-- ---------------------------------------------------------------------------
-- 5. RPC: create_payroll_review_session(p_input jsonb)
--    Allowed: SA, HA, Encoder
--    p_input shape:
--      {
--        "session": {
--          "payroll_file_name": "...",
--          "notes": "..."          -- optional
--        },
--        "items": [
--          {
--            "finding_type": "...",
--            "employee_number": "...",
--            "payroll_full_name": "...",   -- optional
--            "plantilla_full_name": "...", -- optional
--            "payroll_account": "...",     -- optional
--            "payroll_group": "...",       -- optional
--            "plantilla_account": "...",   -- optional
--            "plantilla_group": "...",     -- optional
--            "assigned_account_id": "uuid",
--            "assigned_group_id": "uuid"   -- optional
--          }
--        ]
--      }
--    Returns: { "session_id": "uuid" }
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_payroll_review_session(
  p_input jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id       uuid;
  v_caller_name     text;
  v_session_data    jsonb;
  v_items_data      jsonb;
  v_item            jsonb;
  v_session_id      uuid;
  v_file_name       text;
  v_notes           text;
  v_item_count      int;
  v_finding_type    text;
  v_acc_id          uuid;
BEGIN
  -- RBAC: SA, HA, Encoder
  IF NOT (public.i_have_full_access() OR public.get_my_role_level() = 30) THEN
    RAISE EXCEPTION 'forbidden: Data Team role required'
      USING ERRCODE = '42501';
  END IF;

  v_caller_id   := public.get_my_profile_id();
  v_caller_name := public.get_my_full_name();

  v_session_data := p_input -> 'session';
  v_items_data   := p_input -> 'items';

  -- Validate items present
  IF v_items_data IS NULL OR jsonb_array_length(v_items_data) = 0 THEN
    RAISE EXCEPTION 'items must not be empty'
      USING ERRCODE = '22000';
  END IF;

  v_file_name := btrim(v_session_data ->> 'payroll_file_name');
  IF v_file_name IS NULL OR v_file_name = '' THEN
    RAISE EXCEPTION 'payroll_file_name is required'
      USING ERRCODE = '22000';
  END IF;

  v_notes      := v_session_data ->> 'notes';
  v_item_count := jsonb_array_length(v_items_data);

  -- Pre-validate all items before any insert
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_data)
  LOOP
    v_finding_type := v_item ->> 'finding_type';
    v_acc_id       := (v_item ->> 'assigned_account_id')::uuid;

    -- Reject Clean findings
    IF v_finding_type = 'Clean' THEN
      RAISE EXCEPTION 'finding_type ''Clean'' is not allowed in a review session'
        USING ERRCODE = '22000';
    END IF;

    -- Require assigned_account_id
    IF v_acc_id IS NULL THEN
      RAISE EXCEPTION 'assigned_account_id is required for every item'
        USING ERRCODE = '22000';
    END IF;
  END LOOP;

  -- Insert session
  INSERT INTO public.payroll_review_sessions (
    created_by,
    created_by_name,
    payroll_file_name,
    total_items,
    status,
    notes
  )
  VALUES (
    v_caller_id,
    v_caller_name,
    v_file_name,
    v_item_count,
    'Open',
    v_notes
  )
  RETURNING id INTO v_session_id;

  -- Insert all items atomically
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_data)
  LOOP
    INSERT INTO public.payroll_review_items (
      session_id,
      finding_type,
      employee_number,
      payroll_full_name,
      plantilla_full_name,
      payroll_account,
      payroll_group,
      plantilla_account,
      plantilla_group,
      assigned_account_id,
      assigned_group_id,
      status
    )
    VALUES (
      v_session_id,
      v_item ->> 'finding_type',
      btrim(COALESCE(v_item ->> 'employee_number', '')),
      v_item ->> 'payroll_full_name',
      v_item ->> 'plantilla_full_name',
      v_item ->> 'payroll_account',
      v_item ->> 'payroll_group',
      v_item ->> 'plantilla_account',
      v_item ->> 'plantilla_group',
      (v_item ->> 'assigned_account_id')::uuid,
      (v_item ->> 'assigned_group_id')::uuid,
      'Pending Ops Review'
    );
  END LOOP;

  RETURN jsonb_build_object('session_id', v_session_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. RPC: list_payroll_review_sessions(p_status text default null)
--    Allowed: SA, HA, Encoder
--    Returns: sessions with per-status item count breakdown
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_payroll_review_sessions(
  p_status text DEFAULT NULL
)
RETURNS TABLE (
  id                uuid,
  created_by        uuid,
  created_by_name   text,
  payroll_file_name text,
  total_items       int,
  status            text,
  notes             text,
  closed_by         uuid,
  closed_by_name    text,
  closed_at         timestamptz,
  created_at        timestamptz,
  pending_count     bigint,
  commented_count   bigint,
  needs_fixing_count bigint,
  confirmed_count   bigint,
  not_my_scope_count bigint,
  closed_count      bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT (public.i_have_full_access() OR public.get_my_role_level() = 30) THEN
    RAISE EXCEPTION 'forbidden: Data Team role required'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    s.id,
    s.created_by,
    s.created_by_name,
    s.payroll_file_name,
    s.total_items,
    s.status,
    s.notes,
    s.closed_by,
    s.closed_by_name,
    s.closed_at,
    s.created_at,
    COUNT(i.id) FILTER (WHERE i.status = 'Pending Ops Review')  AS pending_count,
    COUNT(i.id) FILTER (WHERE i.status = 'Ops Commented')       AS commented_count,
    COUNT(i.id) FILTER (WHERE i.status = 'Needs Fixing')        AS needs_fixing_count,
    COUNT(i.id) FILTER (WHERE i.status = 'Confirmed Correct')   AS confirmed_count,
    COUNT(i.id) FILTER (WHERE i.status = 'Not My Scope')        AS not_my_scope_count,
    COUNT(i.id) FILTER (WHERE i.status = 'Closed')              AS closed_count
  FROM  public.payroll_review_sessions s
  LEFT JOIN public.payroll_review_items i ON i.session_id = s.id
  WHERE (p_status IS NULL OR s.status = p_status)
  GROUP BY s.id
  ORDER BY s.created_at DESC;
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. RPC: list_payroll_review_items(p_session_id uuid, p_status text default null)
--    Allowed: SA, HA, Encoder
--    Returns: all items for a session, optional status filter
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_payroll_review_items(
  p_session_id uuid,
  p_status     text DEFAULT NULL
)
RETURNS TABLE (
  id                  uuid,
  session_id          uuid,
  finding_type        text,
  employee_number     text,
  payroll_full_name   text,
  plantilla_full_name text,
  payroll_account     text,
  payroll_group       text,
  plantilla_account   text,
  plantilla_group     text,
  assigned_account_id uuid,
  assigned_group_id   uuid,
  status              text,
  ops_response        text,
  ops_comment         text,
  commented_by        uuid,
  commented_by_name   text,
  commented_at        timestamptz,
  closed_by           uuid,
  closed_by_name      text,
  closed_at           timestamptz,
  created_at          timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT (public.i_have_full_access() OR public.get_my_role_level() = 30) THEN
    RAISE EXCEPTION 'forbidden: Data Team role required'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    i.id,
    i.session_id,
    i.finding_type,
    i.employee_number,
    i.payroll_full_name,
    i.plantilla_full_name,
    i.payroll_account,
    i.payroll_group,
    i.plantilla_account,
    i.plantilla_group,
    i.assigned_account_id,
    i.assigned_group_id,
    i.status,
    i.ops_response,
    i.ops_comment,
    i.commented_by,
    i.commented_by_name,
    i.commented_at,
    i.closed_by,
    i.closed_by_name,
    i.closed_at,
    i.created_at
  FROM  public.payroll_review_items i
  WHERE i.session_id = p_session_id
    AND (p_status IS NULL OR i.status = p_status)
  ORDER BY i.created_at ASC;
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. RPC: list_ops_payroll_review_items(p_status text default null)
--    Allowed: OM only, scoped to assigned_account_id in caller's user_scopes
--    Returns: items assigned to caller's accounts (explicit status filter —
--             Closed items included unless caller filters them out)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_ops_payroll_review_items(
  p_status text DEFAULT NULL
)
RETURNS TABLE (
  id                    uuid,
  session_id            uuid,
  payroll_file_name     text,
  session_created_at    timestamptz,
  finding_type          text,
  employee_number       text,
  payroll_full_name     text,
  plantilla_full_name   text,
  payroll_account       text,
  payroll_group         text,
  plantilla_account     text,
  plantilla_group       text,
  assigned_account_id   uuid,
  assigned_group_id     uuid,
  status                text,
  ops_response          text,
  ops_comment           text,
  commented_by          uuid,
  commented_by_name     text,
  commented_at          timestamptz,
  closed_by             uuid,
  closed_by_name        text,
  closed_at             timestamptz,
  created_at            timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id  uuid;
BEGIN
  IF public.get_my_role_level() != 70 THEN
    RAISE EXCEPTION 'forbidden: Operations Manager role required'
      USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_my_profile_id();

  RETURN QUERY
  SELECT
    i.id,
    i.session_id,
    s.payroll_file_name,
    s.created_at          AS session_created_at,
    i.finding_type,
    i.employee_number,
    i.payroll_full_name,
    i.plantilla_full_name,
    i.payroll_account,
    i.payroll_group,
    i.plantilla_account,
    i.plantilla_group,
    i.assigned_account_id,
    i.assigned_group_id,
    i.status,
    i.ops_response,
    i.ops_comment,
    i.commented_by,
    i.commented_by_name,
    i.commented_at,
    i.closed_by,
    i.closed_by_name,
    i.closed_at,
    i.created_at
  FROM  public.payroll_review_items i
  JOIN  public.payroll_review_sessions s ON s.id = i.session_id
  WHERE (p_status IS NULL OR i.status = p_status)
    AND i.assigned_account_id IN (
      -- group-scoped accounts
      SELECT a.id
      FROM   public.accounts a
      JOIN   public.user_scopes us ON us.group_id = a.group_id
      WHERE  us.user_id     = v_caller_id
        AND  a.is_active    = true
      UNION
      -- direct account-scoped entries
      SELECT us2.account_id
      FROM   public.user_scopes us2
      WHERE  us2.user_id    = v_caller_id
        AND  us2.account_id IS NOT NULL
    )
  ORDER BY i.created_at DESC;
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. RPC: submit_ops_payroll_review_comment(
--      p_item_id    uuid,
--      p_ops_response text,
--      p_comment    text default null
--    )
--    Allowed: OM scoped only
--    - Validates item is in caller scoped account
--    - Rejects Closed items
--    - 'Other' response requires non-empty comment
--    - Maps ops_response → item status
--    - Allows re-submit while not Closed
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_ops_payroll_review_comment(
  p_item_id      uuid,
  p_ops_response text,
  p_comment      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id    uuid;
  v_caller_name  text;
  v_item         record;
  v_new_status   text;
BEGIN
  IF public.get_my_role_level() != 70 THEN
    RAISE EXCEPTION 'forbidden: Operations Manager role required'
      USING ERRCODE = '42501';
  END IF;

  v_caller_id   := public.get_my_profile_id();
  v_caller_name := public.get_my_full_name();

  -- Load item
  SELECT * INTO v_item
  FROM   public.payroll_review_items
  WHERE  id = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'item not found'
      USING ERRCODE = '22000';
  END IF;

  -- Scope check: item must belong to caller's assigned accounts
  IF NOT EXISTS (
    SELECT 1
    FROM (
      SELECT a.id AS account_id
      FROM   public.accounts a
      JOIN   public.user_scopes us ON us.group_id = a.group_id
      WHERE  us.user_id     = v_caller_id
        AND  a.is_active    = true
      UNION
      SELECT us2.account_id
      FROM   public.user_scopes us2
      WHERE  us2.user_id    = v_caller_id
        AND  us2.account_id IS NOT NULL
    ) scoped
    WHERE scoped.account_id = v_item.assigned_account_id
  ) THEN
    RAISE EXCEPTION 'forbidden: item is not within your assigned scope'
      USING ERRCODE = '42501';
  END IF;

  -- Reject Closed items
  IF v_item.status = 'Closed' THEN
    RAISE EXCEPTION 'item is already closed and cannot be updated'
      USING ERRCODE = '22000';
  END IF;

  -- 'Other' requires a non-empty comment
  IF p_ops_response = 'Other' AND (p_comment IS NULL OR btrim(p_comment) = '') THEN
    RAISE EXCEPTION 'comment is required when ops_response is ''Other'''
      USING ERRCODE = '22000';
  END IF;

  -- Map ops_response → new item status
  v_new_status := CASE p_ops_response
    WHEN 'Correct as is'              THEN 'Confirmed Correct'
    WHEN 'Needs fixing'               THEN 'Needs Fixing'
    WHEN 'Wrong account/group'        THEN 'Not My Scope'
    WHEN 'Not under my scope'         THEN 'Not My Scope'
    WHEN 'Employee inactive/resigned' THEN 'Ops Commented'
    WHEN 'Employee transferred'       THEN 'Ops Commented'
    WHEN 'Other'                      THEN 'Ops Commented'
    ELSE NULL
  END;

  IF v_new_status IS NULL THEN
    RAISE EXCEPTION 'invalid ops_response value: %', p_ops_response
      USING ERRCODE = '22000';
  END IF;

  UPDATE public.payroll_review_items
  SET
    ops_response       = p_ops_response,
    ops_comment        = p_comment,
    commented_by       = v_caller_id,
    commented_by_name  = v_caller_name,
    commented_at       = now(),
    status             = v_new_status
  WHERE id = p_item_id;

  RETURN jsonb_build_object(
    'item_id',    p_item_id,
    'new_status', v_new_status
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 10. RPC: close_payroll_review_item(p_item_id uuid)
--     Allowed: SA, HA, Encoder
--     Sets item status → Closed; does not modify Ops comment fields
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.close_payroll_review_item(
  p_item_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id    uuid;
  v_caller_name  text;
BEGIN
  IF NOT (public.i_have_full_access() OR public.get_my_role_level() = 30) THEN
    RAISE EXCEPTION 'forbidden: Data Team role required'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.payroll_review_items WHERE id = p_item_id
  ) THEN
    RAISE EXCEPTION 'item not found'
      USING ERRCODE = '22000';
  END IF;

  v_caller_id   := public.get_my_profile_id();
  v_caller_name := public.get_my_full_name();

  UPDATE public.payroll_review_items
  SET
    status         = 'Closed',
    closed_by      = v_caller_id,
    closed_by_name = v_caller_name,
    closed_at      = now()
  WHERE id = p_item_id;

  RETURN jsonb_build_object('item_id', p_item_id, 'status', 'Closed');
END;
$$;

-- ---------------------------------------------------------------------------
-- 11. RPC: close_payroll_review_session(p_session_id uuid)
--     Allowed: SA, HA, Encoder
--     Sets session status → Closed; does NOT cascade close child items
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.close_payroll_review_session(
  p_session_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id    uuid;
  v_caller_name  text;
BEGIN
  IF NOT (public.i_have_full_access() OR public.get_my_role_level() = 30) THEN
    RAISE EXCEPTION 'forbidden: Data Team role required'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.payroll_review_sessions WHERE id = p_session_id
  ) THEN
    RAISE EXCEPTION 'session not found'
      USING ERRCODE = '22000';
  END IF;

  v_caller_id   := public.get_my_profile_id();
  v_caller_name := public.get_my_full_name();

  UPDATE public.payroll_review_sessions
  SET
    status         = 'Closed',
    closed_by      = v_caller_id,
    closed_by_name = v_caller_name,
    closed_at      = now()
  WHERE id = p_session_id;

  RETURN jsonb_build_object('session_id', p_session_id, 'status', 'Closed');
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. Grants
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.create_payroll_review_session(jsonb)         FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_payroll_review_sessions(text)            FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_payroll_review_items(uuid, text)         FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_ops_payroll_review_items(text)           FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_ops_payroll_review_comment(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.close_payroll_review_item(uuid)               FROM PUBLIC;
REVOKE ALL ON FUNCTION public.close_payroll_review_session(uuid)            FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_payroll_review_session(jsonb)         TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_payroll_review_sessions(text)            TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_payroll_review_items(uuid, text)         TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_ops_payroll_review_items(text)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_ops_payroll_review_comment(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.close_payroll_review_item(uuid)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.close_payroll_review_session(uuid)            TO authenticated;

GRANT SELECT ON public.payroll_review_sessions TO authenticated;
GRANT SELECT ON public.payroll_review_items    TO authenticated;

COMMIT;
