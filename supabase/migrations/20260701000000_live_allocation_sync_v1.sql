-- ============================================================================
-- OHM2026_0072 — Auto-Sync Employee Store Allocations from Live Onboarding (v1)
-- ============================================================================
-- ADDITIVE migration. Does NOT modify or drop any existing migration, view, or
-- RPC. Does NOT modify Import Plantilla / rollback, the CENCOM UI, the legacy
-- COUNT views, or any RLS/RBAC policy. No hard deletes. No DROP CASCADE.
--
-- PROBLEM (confirmed by the read-only audit in the ticket):
--   employee_store_allocations is the canonical operational manpower ledger
--   (OHM2026_0066 Filled HC, OHM2026_0070 roving-aware Open HC). Import Plantilla
--   populates it correctly. But the LIVE onboarding path
--       Vacancy → HR Emploc → Plantilla
--   (confirm_applicant_onboard → move_to_plantilla, link_late_store_to_plantilla,
--   resign_roving_employee, resign_employee/_apply_separation, and the separation
--   trigger fn_plantilla_separation_to_vacancy) creates / mutates plantilla rows
--   and plantilla_store_links WITHOUT writing employee_store_allocations. So live
--   onboarded employees never appear in the ledger → Filled HC / MFR / CENCOM drift
--   vs imported employees, and stale rows linger after separation.
--
-- WHY TRIGGERS, NOT RPC EDITS (same philosophy as OHM2026_0071):
--   move_to_plantilla, resign_*, confirm_applicant_onboard, and the separation
--   path are large, read-only-by-mandate RPCs. Patching each inline is high-risk
--   transcription churn. Every live onboarding/separation footprint change lands
--   at exactly two invariant write points:
--       • public.plantilla            (INSERT a master / status / soft-delete)
--       • public.plantilla_store_links(roving store add / resign / unlink)
--   We normalize at those points: AFTER triggers call one idempotent helper that
--   rebuilds the employee's canonical ACTIVE allocations from the authoritative
--   active links. No onboarding RPC is touched.
--   hr_emploc_store_links is also observed as a roving fallback when a plantilla
--   master already exists but plantilla_store_links are not yet materialized.
--
-- IMPORT BOUNDARY (hard requirement — "Do NOT modify Import Plantilla"):
--   The helper only manages LIVE allocations:
--     • desired footprints come only from plantilla masters with
--       source_employee_import_batch_id/source_baseline_import_batch_id IS NULL,
--     • the stale-deactivation step only touches rows with
--       source_import_batch_id IS NULL.
--   Import-created allocations (source_import_batch_id set) are never read for
--   rebuild and never deactivated by this layer. A purely import-managed employee
--   is skipped entirely (early guard) so import rows are not even re-normalized.
--
-- HISTORY / SAFETY:
--   Stale rows are deactivated (is_active=false, effective_end=CURRENT_DATE), never
--   deleted. New active rows are inserted (never reactivated) so the allocation
--   timeline is preserved. Fractions use the OHM2026_0066 equal-split strategy
--   scoped to LIVE rows so SUM(active LIVE filled_hc)=1.0 exactly.
--   The helper writes only employee_store_allocations — it never touches vacancies,
--   so the vacancy edit-lock trigger is irrelevant here (no lock interaction).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- §1  Central helper — rebuild an employee's canonical LIVE active allocations
-- ----------------------------------------------------------------------------
-- Authoritative active footprint for one employee:
--   Roving   (plantilla.deployment_type='Roving' AND roving_assignment_id NOT NULL):
--            one footprint per ACTIVE plantilla_store_links row.
--   Stationary / pool: one footprint from the plantilla master itself (its vcode).
-- Only LIVE (non-import) occupying masters contribute. VCODE is the
-- manpower-slot identity used to match allocation rows.
--
-- Idempotent. Returns SUM(active filled_hc) for the employee after sync.
CREATE OR REPLACE FUNCTION public.fn_sync_employee_store_allocations(p_employee_no text)
  RETURNS numeric
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_has_live   boolean;
  v_cnt        integer;
  v_each       numeric(8,4);
  v_remainder  numeric(8,4);
  v_first_id   uuid;
  v_total      numeric;
BEGIN
  IF p_employee_no IS NULL THEN
    RETURN NULL;
  END IF;

  -- Early guard: do nothing (and never touch import rows) for an employee that
  -- has neither a LIVE occupying master nor any LIVE allocation to clean up.
  SELECT
    EXISTS (
      SELECT 1 FROM public.plantilla m
       WHERE m.employee_no = p_employee_no
         AND m.is_deleted = false
         AND COALESCE(m.is_archived, false) = false
         AND m.status IN ('Active','On Leave','For Deactivation','Pending Deactivation')
         AND m.source_employee_import_batch_id IS NULL
         AND m.source_baseline_import_batch_id IS NULL
    )
    OR EXISTS (
      SELECT 1 FROM public.employee_store_allocations a
       WHERE a.employee_no = p_employee_no
         AND a.is_active
         AND a.source_import_batch_id IS NULL
    )
  INTO v_has_live;

  IF NOT v_has_live THEN
    RETURN NULL;
  END IF;

  -- ── Deactivate LIVE active allocations no longer in the desired footprint ──
  WITH masters AS (
    SELECT m.id AS plantilla_id, m.deployment_type, m.roving_assignment_id,
           m.store_id, m.vcode, m.store_name, m.account_id, m.hr_emploc_id
    FROM public.plantilla m
    WHERE m.employee_no = p_employee_no
      AND m.is_deleted = false
      AND COALESCE(m.is_archived, false) = false
      AND m.status IN ('Active','On Leave','For Deactivation','Pending Deactivation')
      AND m.source_employee_import_batch_id IS NULL
      AND m.source_baseline_import_batch_id IS NULL
  ),
  footprints AS (
    -- Roving: one per active store link
    SELECT m.plantilla_id, psl.vcode, psl.store_name,
           NULL::uuid AS store_id_hint, NULL::uuid AS account_id_hint
    FROM masters m
    JOIN public.plantilla_store_links psl
      ON psl.plantilla_id = m.plantilla_id
     AND psl.status = 'Active'
     AND psl.deleted_at IS NULL
    WHERE m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL
    UNION ALL
    -- Roving fallback: confirmed HR Emploc links if plantilla links are missing.
    SELECT m.plantilla_id, hsl.vcode, hsl.store_name,
           NULL::uuid AS store_id_hint, NULL::uuid AS account_id_hint
    FROM masters m
    JOIN public.hr_emploc_store_links hsl
      ON hsl.deleted_at IS NULL
     AND hsl.status = 'Confirmed'
     AND (
       hsl.hr_emploc_id = m.hr_emploc_id
       OR hsl.roving_assignment_id = m.roving_assignment_id
     )
    WHERE m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL
    UNION ALL
    -- Stationary / pool: the master itself (keyed by its vcode)
    SELECT m.plantilla_id, m.vcode, m.store_name,
           m.store_id AS store_id_hint, m.account_id AS account_id_hint
    FROM masters m
    WHERE NOT (m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL)
      AND m.vcode IS NOT NULL
  ),
  resolved AS (
    SELECT DISTINCT ON (f.plantilla_id, upper(f.vcode))
           f.plantilla_id, f.vcode
    FROM footprints f
    WHERE f.vcode IS NOT NULL
  )
  UPDATE public.employee_store_allocations esa
     SET is_active = false,
         effective_end = CURRENT_DATE
   WHERE esa.employee_no = p_employee_no
     AND esa.is_active
     AND esa.source_import_batch_id IS NULL
     AND NOT EXISTS (
       SELECT 1 FROM resolved r
       WHERE r.plantilla_id = esa.plantilla_id
         AND upper(r.vcode) = upper(esa.vcode)
     );

  -- ── Insert allocations for desired footprints not already active ───────────
  WITH masters AS (
    SELECT m.id AS plantilla_id, m.deployment_type, m.roving_assignment_id,
           m.store_id, m.vcode, m.store_name, m.account_id, m.hr_emploc_id
    FROM public.plantilla m
    WHERE m.employee_no = p_employee_no
      AND m.is_deleted = false
      AND COALESCE(m.is_archived, false) = false
      AND m.status IN ('Active','On Leave','For Deactivation','Pending Deactivation')
      AND m.source_employee_import_batch_id IS NULL
      AND m.source_baseline_import_batch_id IS NULL
  ),
  footprints AS (
    SELECT m.plantilla_id, psl.vcode, psl.store_name,
           NULL::uuid AS store_id_hint, NULL::uuid AS account_id_hint
    FROM masters m
    JOIN public.plantilla_store_links psl
      ON psl.plantilla_id = m.plantilla_id
     AND psl.status = 'Active'
     AND psl.deleted_at IS NULL
    WHERE m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL
    UNION ALL
    SELECT m.plantilla_id, hsl.vcode, hsl.store_name,
           NULL::uuid AS store_id_hint, NULL::uuid AS account_id_hint
    FROM masters m
    JOIN public.hr_emploc_store_links hsl
      ON hsl.deleted_at IS NULL
     AND hsl.status = 'Confirmed'
     AND (
       hsl.hr_emploc_id = m.hr_emploc_id
       OR hsl.roving_assignment_id = m.roving_assignment_id
     )
    WHERE m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL
    UNION ALL
    SELECT m.plantilla_id, m.vcode, m.store_name,
           m.store_id AS store_id_hint, m.account_id AS account_id_hint
    FROM masters m
    WHERE NOT (m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL)
      AND m.vcode IS NOT NULL
  ),
  resolved AS (
    SELECT DISTINCT ON (f.plantilla_id, upper(f.vcode))
           f.plantilla_id,
           f.vcode,
           COALESCE(f.store_id_hint, st.id, va.store_id)        AS store_id,
           COALESCE(st.store_name, f.store_name)                AS store_name,
           COALESCE(f.account_id_hint, st.account_id, va.account_id) AS account_id,
           COALESCE(st.group_id, acc.group_id)                  AS group_id
    FROM footprints f
    LEFT JOIN LATERAL (
      SELECT s.id, s.store_name, s.account_id, s.group_id
      FROM public.stores s
      WHERE upper(s.vcode) = upper(f.vcode) AND s.status = 'active'
      ORDER BY s.created_at
      LIMIT 1
    ) st ON true
    LEFT JOIN LATERAL (
      SELECT v.store_id, v.account_id
      FROM public.vacancies v
      WHERE v.vcode = f.vcode
      ORDER BY v.created_at
      LIMIT 1
    ) va ON true
    LEFT JOIN public.accounts acc
      ON acc.id = COALESCE(f.account_id_hint, st.account_id, va.account_id)
    WHERE f.vcode IS NOT NULL
  )
  INSERT INTO public.employee_store_allocations (
    plantilla_id, employee_no, roving_group_id,
    store_id, vcode, store_name,
    account_id, group_id,
    filled_hc, active_store_count,
    effective_start, is_active,
    source_import_batch_id, created_by
  )
  SELECT
    r.plantilla_id, p_employee_no, NULL,
    r.store_id, r.vcode, r.store_name,
    r.account_id, r.group_id,
    1, 1,                       -- placeholders; normalized below
    CURRENT_DATE, true,
    NULL, NULL                  -- LIVE allocation: source_import_batch_id stays NULL
  FROM resolved r
  WHERE NOT EXISTS (
    SELECT 1 FROM public.employee_store_allocations e
    WHERE e.employee_no = p_employee_no
      AND e.is_active
      AND e.plantilla_id = r.plantilla_id
      AND upper(e.vcode) = upper(r.vcode)
  );

  -- ── Collapse duplicate LIVE active footprints, preserving one active row ──
  WITH ranked AS (
    SELECT e.id,
           row_number() OVER (
             PARTITION BY e.employee_no, e.plantilla_id, upper(COALESCE(e.vcode, ''))
             ORDER BY e.effective_start, e.created_at, e.id
           ) AS rn
    FROM public.employee_store_allocations e
    WHERE e.employee_no = p_employee_no
      AND e.is_active
      AND e.source_import_batch_id IS NULL
  )
  UPDATE public.employee_store_allocations e
     SET is_active = false,
         effective_end = CURRENT_DATE
    FROM ranked r
   WHERE e.id = r.id
     AND r.rn > 1;

  -- ── Normalize LIVE fractions (SUM(filled_hc)=1.0 exactly) ────────────────
  SELECT count(*) INTO v_cnt
  FROM public.employee_store_allocations
  WHERE employee_no = p_employee_no
    AND is_active
    AND source_import_batch_id IS NULL;

  IF v_cnt = 0 THEN
    RETURN 0;
  END IF;

  v_each      := round(1.0 / v_cnt, 4);
  v_remainder := round(1.0 - (v_each * v_cnt), 4);

  SELECT id INTO v_first_id
  FROM public.employee_store_allocations
  WHERE employee_no = p_employee_no
    AND is_active
    AND source_import_batch_id IS NULL
  ORDER BY effective_start, created_at, id
  LIMIT 1;

  UPDATE public.employee_store_allocations
     SET active_store_count = v_cnt,
         filled_hc = CASE WHEN id = v_first_id THEN v_each + v_remainder ELSE v_each END
   WHERE employee_no = p_employee_no
     AND is_active
     AND source_import_batch_id IS NULL;

  SELECT COALESCE(sum(filled_hc), 0) INTO v_total
  FROM public.employee_store_allocations
  WHERE employee_no = p_employee_no
    AND is_active
    AND source_import_batch_id IS NULL;

  RETURN v_total;
END;
$function$;

COMMENT ON FUNCTION public.fn_sync_employee_store_allocations(text) IS
  'OHM2026_0072: rebuilds an employee''s canonical LIVE active employee_store_allocations '
  'from authoritative active sources (plantilla master for stationary/pool; active '
  'plantilla_store_links plus confirmed hr_emploc_store_links fallback for roving). '
  'Deactivates stale LIVE rows (history preserved), inserts missing footprints, normalizes LIVE fractions. '
  'NEVER reads or writes import-sourced allocations (source_import_batch_id set). Idempotent.';

REVOKE ALL ON FUNCTION public.fn_sync_employee_store_allocations(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_sync_employee_store_allocations(text) TO service_role;

-- ----------------------------------------------------------------------------
-- §2  Trigger glue — fire the helper at the live footprint write points
-- ----------------------------------------------------------------------------
-- Resolves the affected employee_no (directly on plantilla, via plantilla_id on
-- plantilla_store_links, or via roving HR Emploc linkage) and delegates to the
-- helper. SECURITY DEFINER so the helper's allocation writes run with owner
-- authority regardless of the calling RPC's user (employee_store_allocations has
-- INSERT/UPDATE revoked from authenticated).
CREATE OR REPLACE FUNCTION public.fn_trg_sync_employee_allocations()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_employee_no text;
BEGIN
  IF TG_TABLE_NAME = 'plantilla' THEN
    IF TG_OP = 'UPDATE'
       AND OLD.employee_no IS NOT NULL
       AND OLD.employee_no IS DISTINCT FROM NEW.employee_no THEN
      PERFORM public.fn_sync_employee_store_allocations(OLD.employee_no);
    END IF;
    v_employee_no := NEW.employee_no;
  ELSIF TG_TABLE_NAME = 'plantilla_store_links' THEN
    -- plantilla_store_links: only sync for LIVE (non-import) masters.
    SELECT p.employee_no INTO v_employee_no
    FROM public.plantilla p
    WHERE p.id = NEW.plantilla_id
      AND p.source_employee_import_batch_id IS NULL
      AND p.source_baseline_import_batch_id IS NULL;
  ELSE
    -- hr_emploc_store_links: fallback only matters after a LIVE roving master
    -- exists for the same HR Emploc or roving assignment.
    SELECT p.employee_no INTO v_employee_no
    FROM public.plantilla p
    WHERE p.is_deleted = false
      AND COALESCE(p.is_archived, false) = false
      AND p.source_employee_import_batch_id IS NULL
      AND p.source_baseline_import_batch_id IS NULL
      AND (
        p.hr_emploc_id = NEW.hr_emploc_id
        OR p.roving_assignment_id = NEW.roving_assignment_id
      )
    ORDER BY p.created_at DESC
    LIMIT 1;
  END IF;

  IF v_employee_no IS NOT NULL THEN
    PERFORM public.fn_sync_employee_store_allocations(v_employee_no);
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.fn_trg_sync_employee_allocations() IS
  'AFTER-trigger glue (OHM2026_0072): on a live plantilla master, plantilla_store_links, '
  'or hr_emploc_store_links write, calls fn_sync_employee_store_allocations(employee_no) so the allocation ledger '
  'tracks the live onboarding / separation footprint. Skips import-origin masters. Idempotent.';

REVOKE ALL ON FUNCTION public.fn_trg_sync_employee_allocations() FROM PUBLIC, anon;

-- Plantilla master INSERT: stationary/pool onboard creates the footprint here;
-- roving master is inserted first (footprint completed by the store-link trigger
-- as each link lands). Import-origin rows are excluded by the WHEN guard.
DROP TRIGGER IF EXISTS trg_sync_alloc_plantilla_ins ON public.plantilla;
CREATE TRIGGER trg_sync_alloc_plantilla_ins
  AFTER INSERT ON public.plantilla
  FOR EACH ROW
  WHEN (NEW.source_employee_import_batch_id IS NULL
        AND NEW.source_baseline_import_batch_id IS NULL
        AND NEW.employee_no IS NOT NULL)
  EXECUTE FUNCTION public.fn_trg_sync_employee_allocations();

-- Plantilla master state change: separation (Active→Inactive), soft-delete,
-- archival, or a deployment-type/roving reclassification must re-sync (and
-- deactivate stale rows).
DROP TRIGGER IF EXISTS trg_sync_alloc_plantilla_upd ON public.plantilla;
CREATE TRIGGER trg_sync_alloc_plantilla_upd
  AFTER UPDATE OF employee_no, status, is_deleted, is_archived, deployment_type,
                  roving_assignment_id, store_id, vcode, store_name, account_id
  ON public.plantilla
  FOR EACH ROW
  WHEN (NEW.source_employee_import_batch_id IS NULL
        AND NEW.source_baseline_import_batch_id IS NULL
        AND (NEW.employee_no IS NOT NULL OR OLD.employee_no IS NOT NULL)
        AND (OLD.employee_no       IS DISTINCT FROM NEW.employee_no
          OR OLD.status            IS DISTINCT FROM NEW.status
          OR OLD.is_deleted        IS DISTINCT FROM NEW.is_deleted
          OR OLD.is_archived       IS DISTINCT FROM NEW.is_archived
          OR OLD.deployment_type   IS DISTINCT FROM NEW.deployment_type
          OR OLD.roving_assignment_id IS DISTINCT FROM NEW.roving_assignment_id
          OR OLD.store_id          IS DISTINCT FROM NEW.store_id
          OR OLD.vcode             IS DISTINCT FROM NEW.vcode
          OR OLD.store_name        IS DISTINCT FROM NEW.store_name
          OR OLD.account_id        IS DISTINCT FROM NEW.account_id))
  EXECUTE FUNCTION public.fn_trg_sync_employee_allocations();

-- Roving store-link write: store added (link_late_store_to_plantilla), resigned,
-- or unlinked. Re-syncs the roving footprint and re-splits the fraction.
DROP TRIGGER IF EXISTS trg_sync_alloc_plantilla_link ON public.plantilla_store_links;
CREATE TRIGGER trg_sync_alloc_plantilla_link
  AFTER INSERT OR UPDATE ON public.plantilla_store_links
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_sync_employee_allocations();

-- HR Emploc store-link fallback: if a roving plantilla master already exists
-- but its plantilla_store_links have not materialized, confirmed HR Emploc links
-- can still keep the operational allocation ledger accurate.
DROP TRIGGER IF EXISTS trg_sync_alloc_hr_emploc_link ON public.hr_emploc_store_links;
CREATE TRIGGER trg_sync_alloc_hr_emploc_link
  AFTER INSERT OR UPDATE OF status, deleted_at, vcode, store_name, vacancy_id
  ON public.hr_emploc_store_links
  FOR EACH ROW
  WHEN (NEW.roving_assignment_id IS NOT NULL)
  EXECUTE FUNCTION public.fn_trg_sync_employee_allocations();

-- ----------------------------------------------------------------------------
-- §3  Batch backfill — materialize allocations for existing LIVE employees
-- ----------------------------------------------------------------------------
-- Idempotent. Covers employees onboarded live before this migration who have no
-- (or stale) allocation rows. Import-managed employees are skipped by the helper.
CREATE OR REPLACE FUNCTION public.fn_backfill_live_employee_allocations()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  r       record;
  v_total integer := 0;
BEGIN
  FOR r IN
    SELECT DISTINCT m.employee_no
    FROM public.plantilla m
    WHERE m.employee_no IS NOT NULL
      AND m.is_deleted = false
      AND COALESCE(m.is_archived, false) = false
      AND m.status IN ('Active','On Leave','For Deactivation','Pending Deactivation')
      AND m.source_employee_import_batch_id IS NULL
      AND m.source_baseline_import_batch_id IS NULL
  LOOP
    PERFORM public.fn_sync_employee_store_allocations(r.employee_no);
    v_total := v_total + 1;
  END LOOP;
  RETURN v_total;
END;
$function$;

COMMENT ON FUNCTION public.fn_backfill_live_employee_allocations() IS
  'OHM2026_0072: runs fn_sync_employee_store_allocations for every LIVE (non-import) '
  'occupying plantilla employee. Idempotent; returns employees processed.';

REVOKE ALL ON FUNCTION public.fn_backfill_live_employee_allocations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_backfill_live_employee_allocations() TO service_role;

-- One-time backfill of existing live-onboarded employees.
SELECT public.fn_backfill_live_employee_allocations();

COMMIT;
