-- Migration: 20262406000005_security_fix_public_rls_disabled
-- Created: 2026-06-24
-- Purpose: Enable RLS on 8 public tables flagged by Supabase Security Advisor and lock backup tables from client access.
--
-- Smoke Tests:
-- S1: SELECT * FROM plantilla_store_links as anon/authenticated with no scope → 0 rows (policy filters)
-- S2: SELECT * FROM backup_esa_ohm2026_0139 as anon or authenticated → permission denied (no policies)
-- S3: Authenticated user with valid account scope can SELECT from plantilla_store_links and hr_emploc_store_links
--
-- Rollback (run manually — no auto-rollback):
--   ALTER TABLE public.plantilla_store_links DISABLE ROW LEVEL SECURITY;
--   ALTER TABLE public.hr_emploc_store_links DISABLE ROW LEVEL SECURITY;
--   ALTER TABLE public.backup_esa_ohm2026_0139 DISABLE ROW LEVEL SECURITY;
--   ALTER TABLE public.backup_plantilla_ohm2026_0139 DISABLE ROW LEVEL SECURITY;
--   ALTER TABLE public.backup_stores_ohm2026_0139 DISABLE ROW LEVEL SECURITY;
--   ALTER TABLE public._backup_plantilla_slots_ohm2026_0141 DISABLE ROW LEVEL SECURITY;
--   ALTER TABLE public._backup_slot_history_ohm2026_0141 DISABLE ROW LEVEL SECURITY;
--   ALTER TABLE public._backup_vacancies_ohm2026_0141 DISABLE ROW LEVEL SECURITY;
--   GRANT SELECT, INSERT, UPDATE, DELETE ON public.backup_esa_ohm2026_0139 TO authenticated;
--   GRANT SELECT, INSERT, UPDATE, DELETE ON public.backup_plantilla_ohm2026_0139 TO authenticated;
--   GRANT SELECT, INSERT, UPDATE, DELETE ON public.backup_stores_ohm2026_0139 TO authenticated;
--   GRANT SELECT, INSERT, UPDATE, DELETE ON public._backup_plantilla_slots_ohm2026_0141 TO authenticated;
--   GRANT SELECT, INSERT, UPDATE, DELETE ON public._backup_slot_history_ohm2026_0141 TO authenticated;
--   GRANT SELECT, INSERT, UPDATE, DELETE ON public._backup_vacancies_ohm2026_0141 TO authenticated;

BEGIN;

-- ============================================================
-- SECTION 1: OPERATIONAL TABLES
-- plantilla_store_links and hr_emploc_store_links
-- These tables carry live roving-employee store assignment data.
-- Mutations flow exclusively through SECURITY DEFINER RPCs —
-- no client INSERT/UPDATE/DELETE policies are created here.
-- ============================================================

-- ---- plantilla_store_links ----

ALTER TABLE public.plantilla_store_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "plantilla_store_links_select_scoped" ON public.plantilla_store_links;

CREATE POLICY "plantilla_store_links_select_scoped"
  ON public.plantilla_store_links
  FOR SELECT
  TO authenticated
  USING (
    i_have_full_access()
    OR EXISTS (
      SELECT 1
        FROM public.plantilla p
       WHERE p.id = plantilla_store_links.plantilla_id
         AND p.account_id::text = ANY(get_my_allowed_accounts())
    )
  );

-- ---- hr_emploc_store_links ----

ALTER TABLE public.hr_emploc_store_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "hr_emploc_store_links_select_scoped" ON public.hr_emploc_store_links;

CREATE POLICY "hr_emploc_store_links_select_scoped"
  ON public.hr_emploc_store_links
  FOR SELECT
  TO authenticated
  USING (
    i_have_full_access()
    OR EXISTS (
      SELECT 1
        FROM public.hr_emploc h
       WHERE h.id = hr_emploc_store_links.hr_emploc_id
         AND h.account_id::text = ANY(get_my_allowed_accounts())
    )
  );

-- ============================================================
-- SECTION 2: BACKUP / INTERNAL TABLES
-- These tables are point-in-time snapshots used for recovery
-- and data auditing only. They must never be accessible to
-- client roles. RLS is enabled and all anon/authenticated
-- grants are revoked — no policies are created intentionally,
-- resulting in a deny-all state for all client roles.
-- Backend service_role access is unaffected.
--
-- Existence-safe: each table is locked only if it exists in
-- the current database. Backup tables may be absent on staging
-- or freshly cloned environments — skipping silently is correct.
-- ============================================================

DO $$
DECLARE
  v_tbl text;
  v_tables text[] := ARRAY[
    'backup_esa_ohm2026_0139',           -- ESA snapshot (migration ohm2026_0139)
    'backup_plantilla_ohm2026_0139',     -- Plantilla snapshot (migration ohm2026_0139)
    'backup_stores_ohm2026_0139',        -- Stores snapshot (migration ohm2026_0139)
    '_backup_plantilla_slots_ohm2026_0141', -- Plantilla slots snapshot (migration ohm2026_0141)
    '_backup_slot_history_ohm2026_0141', -- Slot history snapshot (migration ohm2026_0141)
    '_backup_vacancies_ohm2026_0141'     -- Vacancies snapshot (migration ohm2026_0141)
  ];
BEGIN
  FOREACH v_tbl IN ARRAY v_tables LOOP
    -- Intentionally locked when present: no client policies. Service_role only.
    IF to_regclass('public.' || v_tbl) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_tbl);
      EXECUTE format('REVOKE ALL ON public.%I FROM anon', v_tbl);
      EXECUTE format('REVOKE ALL ON public.%I FROM authenticated', v_tbl);
    END IF;
  END LOOP;
END;
$$;

COMMIT;
