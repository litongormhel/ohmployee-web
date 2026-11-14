-- Migration: 20262606000111_coverage_group_universal_store_picker.sql
-- Description:
-- 1. Upgrade public.get_coverage_group_eligible_stores to return ALL active stores
--    under the account, regardless of whether they are vacant or have an employee,
--    removing restrictive slot/vacancy predicates.
-- 2. Clean up empty test coverage groups CG-FG1-0002 and CG-FG1-0003 in Forever Office
--    so their 5 member stores are released back to free stationary stores.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_coverage_group_eligible_stores(p_account_id uuid)
 RETURNS TABLE(store_id uuid, store_name text, account_id uuid, area_city text, area_province text, already_grouped_code text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_role      text;
BEGIN
  SELECT id INTO v_caller_id
  FROM public.users_profile
  WHERE auth_user_id = auth.uid()
    AND is_active = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found' USING ERRCODE = '42501';
  END IF;

  SELECT r.role_name INTO v_role
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.id = v_caller_id;

  IF v_role NOT IN ('Super Admin', 'Head Admin', 'Encoder') THEN
    RAISE EXCEPTION 'forbidden: Data Team role required' USING ERRCODE = '42501';
  END IF;

  IF v_role = 'Encoder'
     AND NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: account not in caller scope' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.accounts a
    WHERE a.id = p_account_id
      AND a.is_active = true
      AND lower(COALESCE(a.status, 'active')) <> 'archived'
  ) THEN
    RAISE EXCEPTION 'account not found or archived' USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
  SELECT DISTINCT ON (s.id)
    s.id AS store_id,
    s.store_name,
    s.account_id,
    COALESCE(s.area_city, '') AS area_city,
    COALESCE(s.area_province, '') AS area_province,
    (
      SELECT cg.coverage_code
      FROM public.coverage_group_stores cgs2
      JOIN public.coverage_groups cg
        ON cg.id = cgs2.coverage_group_id
       AND cg.archived_at IS NULL
       AND lower(COALESCE(cg.status, '')) <> 'archived'
      WHERE cgs2.store_id = s.id
        AND cgs2.archived_at IS NULL
      LIMIT 1
    ) AS already_grouped_code
  FROM public.stores s
  WHERE s.account_id = p_account_id
    AND s.is_active = true
    AND lower(COALESCE(s.status, 'active')) <> 'archived'
  ORDER BY s.id, s.store_name;
END;
$function$;

-- Archive empty test groups CG-FG1-0002 and CG-FG1-0003 (0 employees, 0 requests)
UPDATE public.coverage_groups
SET status = 'archived',
    archived_at = now(),
    is_archived = true
WHERE id IN ('a2662b6e-f248-4c47-8f71-979683ff24a8', '26aa319f-12a3-41be-98cb-711ce98c9dc5')
  AND status = 'open';

UPDATE public.coverage_group_stores
SET archived_at = now()
WHERE coverage_group_id IN ('a2662b6e-f248-4c47-8f71-979683ff24a8', '26aa319f-12a3-41be-98cb-711ce98c9dc5');

COMMIT;
