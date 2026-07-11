-- Migration: 20261215000013_fix_pool_request_om_scope.sql
-- Prompt:    ohm#poolhist002
-- Goal:      Fix Workforce Pool Request History scoped visibility for OM.
--
-- Root cause:
--   workforce_pool_requests.requesting_account stores the pool account name
--   ('MOSES HQ') when an Ops user creates a pool request. The previous SELECT
--   policy checked:
--
--     requesting_account = ANY(get_my_allowed_accounts())
--
--   This fails because 'MOSES HQ' (the pool account) is never in the OM's
--   operational account scope.
--
-- Fix (scoped — NOT a global Ops bypass):
--   Add a constrained OM visibility clause that requires:
--     - is_ops_request = true  (only Ops-submitted requests, not Data Team)
--     - role level 40–70       (OM / HRCO / ATL / TL only)
--     - AND one of:
--         • created_by = auth.uid()::text   (they personally submitted it)
--         • requesting_store_id in their scoped stores via user_scopes
--
--   This ensures an OM sees only pool requests they created or that reference
--   a store in their account scope. They cannot see other accounts' requests.
--
-- Policies replaced:
--   wpr_read_data_team_or_scoped  on workforce_pool_requests
--   wpri_read_data_team_or_scoped on workforce_pool_request_items
--
-- Preserved:
--   SA / HA / Encoder full access (unchanged)
--   requesting_account name match for non-pool / non-MOSES HQ scoped requests
--   All write policies (wpr_write_data_team, wpri_write_data_team) untouched
--   Request creation RPC behavior untouched

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. workforce_pool_requests — fix SELECT policy
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "wpr_read_data_team_or_scoped" ON public.workforce_pool_requests;

CREATE POLICY "wpr_read_data_team_or_scoped"
ON public.workforce_pool_requests
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
  (deleted_at IS NULL)
  AND (
    -- Data Team / Admin: full visibility (unchanged)
    (public.get_my_role_level() = ANY (ARRAY[100, 90, 30]))
    OR public.i_have_full_access()

    -- Non-pool or non-MOSES-HQ requests: match on requesting_account name (unchanged)
    OR (requesting_account = ANY (public.get_my_allowed_accounts()))

    -- Pool Ops requests: scoped to creator or requesting_store in OM's stores.
    -- Constrained by is_ops_request=true so Data Team auto-approved requests
    -- are NOT exposed through this clause.
    OR (
      is_ops_request = true
      AND public.get_my_role_level() BETWEEN 40 AND 70
      AND (
        -- OM who submitted this request can always see it
        created_by = auth.uid()::text
        -- OR any OM whose account scope covers the requested store
        OR requesting_store_id IN (
          SELECT s.id
          FROM public.stores s
          INNER JOIN public.user_scopes us ON us.account_id = s.account_id
          WHERE us.user_id = public.get_my_profile_id()
        )
      )
    )
  )
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. workforce_pool_request_items — fix SELECT policy
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "wpri_read_data_team_or_scoped" ON public.workforce_pool_request_items;

CREATE POLICY "wpri_read_data_team_or_scoped"
ON public.workforce_pool_request_items
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
  -- Data Team / Admin: full visibility (unchanged)
  (public.get_my_role_level() = ANY (ARRAY[100, 90, 30]))
  OR public.i_have_full_access()

  -- Non-pool: parent request visible via requesting_account name (unchanged)
  OR EXISTS (
    SELECT 1
    FROM public.workforce_pool_requests r
    WHERE r.id = workforce_pool_request_items.request_id
      AND r.deleted_at IS NULL
      AND r.requesting_account = ANY (public.get_my_allowed_accounts())
  )

  -- Pool Ops: items visible when parent request is scoped to this OM
  OR (
    public.get_my_role_level() BETWEEN 40 AND 70
    AND EXISTS (
      SELECT 1
      FROM public.workforce_pool_requests r
      WHERE r.id = workforce_pool_request_items.request_id
        AND r.deleted_at IS NULL
        AND r.is_ops_request = true
        AND (
          r.created_by = auth.uid()::text
          OR r.requesting_store_id IN (
            SELECT s.id
            FROM public.stores s
            INNER JOIN public.user_scopes us ON us.account_id = s.account_id
            WHERE us.user_id = public.get_my_profile_id()
          )
        )
    )
  )
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Smoke-test queries (run manually as each role to verify — comments only)
-- ─────────────────────────────────────────────────────────────────────────────

-- [1] OM can see their own submitted pool requests:
--   SET ROLE authenticated; -- signed in as omg3@ohmployee.com
--   SELECT id, requesting_account, is_ops_request, created_by
--   FROM workforce_pool_requests
--   WHERE is_ops_request = true;
--   → Expected: 10 rows (the OM's own submissions)

-- [2] OM cannot see other accounts' pool requests:
--   SELECT id FROM workforce_pool_requests
--   WHERE is_ops_request = true
--     AND created_by != auth.uid()::text
--     AND (requesting_store_id IS NULL
--       OR requesting_store_id NOT IN (
--         SELECT s.id FROM stores s
--         JOIN user_scopes us ON us.account_id = s.account_id
--         WHERE us.user_id = get_my_profile_id()
--       ));
--   → Expected: 0 rows (RLS blocks unrelated requests)

-- [3] SA / HA see all requests:
--   SET ROLE authenticated; -- signed in as superadmin or headAdmin
--   SELECT COUNT(*) FROM workforce_pool_requests;
--   → Expected: all rows including Data Team and Ops requests

-- [4] VCODE chips visible after parent request is visible:
--   SELECT wpr.id, wpri.vcode
--   FROM workforce_pool_requests wpr
--   JOIN workforce_pool_request_items wpri ON wpri.request_id = wpr.id;
--   → Expected (OM): rows for the OM's requests with VCODEs
--   → Expected (SA): all rows
