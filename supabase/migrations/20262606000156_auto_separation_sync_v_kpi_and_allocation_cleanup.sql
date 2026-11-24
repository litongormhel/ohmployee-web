-- Migration: 20262606000156_auto_separation_sync_v_kpi_and_allocation_cleanup.sql
-- Purpose:
-- 1. ADR-001 Rule 2 (Hired HC Source) & Invariant 19 (Auto-Inactive on Separation Date):
--    Harden public.v_account_allocation_kpi so actual_hc and filled_hc derive STRICTLY
--    from active, non-separated employees in public.plantilla (status = 'Active' AND date_of_separation > CURRENT_DATE).
-- 2. Harden public.fn_trg_plantilla_vacate_slot_on_inactive to automatically deactivate
--    public.employee_store_allocations (is_active = false) upon Inactive / Deactivated transition.
-- 3. Harden public.fn_plantilla_separation_to_vacancy filter logic to recognize 'Pending Deactivation'
--    as a valid originating status, ensuring separation workflows properly trigger vacancy reopen.
-- 4. Systematic data cleanup:
--    Transition all employees with effective date_of_separation (<= CURRENT_DATE) to 'Inactive',
--    deactivate their store allocations, and vacate active slots.

BEGIN;

-- ── §1. Harden v_account_allocation_kpi ───────────────────────────────────────

CREATE OR REPLACE VIEW public.v_account_allocation_kpi
  WITH (security_invoker = true)
AS
WITH filled AS (
  SELECT a.account_id,
         round(COALESCE(sum(a.filled_hc), 0), 4) AS filled_hc,
         count(DISTINCT a.employee_no)            AS actual_hc
  FROM public.employee_store_allocations a
  JOIN public.plantilla p ON p.id = a.plantilla_id
  WHERE a.is_active
    AND p.status = 'Active'
    AND (p.date_of_separation IS NULL OR p.date_of_separation > CURRENT_DATE)
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
  GROUP BY a.account_id
),
pipeline AS (
  SELECT he.account_id,
         count(*) AS pipeline_count
  FROM public.hr_emploc he
  LEFT JOIN public.vacancies v ON v.id = he.vacancy_id
  WHERE he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
    AND he.deleted_at IS NULL
    AND he.coverage_slot_id IS NULL
    AND COALESCE(v.is_pool_vacancy, false) = false
  GROUP BY he.account_id
),
coverage_slot_kpi AS (
  SELECT
    cg.account_id,
    COUNT(*) FILTER (WHERE cs.slot_status = 'active')::numeric AS filled_hc,
    CASE
      WHEN COUNT(DISTINCT cs.current_occupant_plantilla_id)
           FILTER (WHERE cs.slot_status = 'active'
                   AND cs.current_occupant_plantilla_id IS NOT NULL) > 0
        THEN COUNT(DISTINCT cs.current_occupant_plantilla_id)
             FILTER (WHERE cs.slot_status = 'active'
                     AND cs.current_occupant_plantilla_id IS NOT NULL)
      ELSE COUNT(*) FILTER (WHERE cs.slot_status = 'active')
    END AS actual_hc,
    COUNT(*) FILTER (WHERE cs.slot_status IN ('pipeline', 'hr_processing')) AS pipeline_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'open')::numeric                AS slot_vacant_hc
  FROM public.coverage_slots cs
  JOIN public.coverage_groups cg ON cg.id = cs.coverage_group_id
  LEFT JOIN public.plantilla cp ON cp.id = cs.current_occupant_plantilla_id
  WHERE cg.archived_at IS NULL
    AND (
      cp.id IS NULL 
      OR (
        cp.status = 'Active' 
        AND (cp.date_of_separation IS NULL OR cp.date_of_separation > CURRENT_DATE)
        AND COALESCE(cp.is_deleted, false) = false
        AND COALESCE(cp.is_archived, false) = false
      )
    )
  GROUP BY cg.account_id
),
slot_vacant_non_roving AS (
  SELECT
    ps.account_id,
    COUNT(*) FILTER (WHERE ps.slot_status IN ('open', 'pipeline')) AS vacant_slots
  FROM public.plantilla_slots ps
  INNER JOIN public.vacancies v
    ON  v.vcode = ps.legacy_vcode
   AND  v.deleted_at IS NULL
   AND  COALESCE(v.is_archived, false)    = false
   AND  COALESCE(v.is_pool_vacancy, false) = false
  WHERE ps.is_roving    = false
    AND ps.legacy_vcode IS NOT NULL
    AND ps.account_id   IS NOT NULL
  GROUP BY ps.account_id
),
slot_vacant_roving AS (
  SELECT
    ps.account_id,
    SUM(
      CASE WHEN ps.slot_status IN ('open', 'pipeline')
           THEN 1.0 / NULLIF(grp.total_slots::numeric, 0)
           ELSE 0.0
      END
    ) AS vacant_hc
  FROM public.plantilla_slots ps
  JOIN (
    SELECT source_hc_request_id,
           COUNT(*) AS total_slots
    FROM public.plantilla_slots
    WHERE is_roving = true
      AND source_hc_request_id IS NOT NULL
    GROUP BY source_hc_request_id
  ) grp ON grp.source_hc_request_id = ps.source_hc_request_id
  WHERE ps.is_roving            = true
    AND ps.source_hc_request_id IS NOT NULL
    AND ps.account_id           IS NOT NULL
  GROUP BY ps.account_id
),
vacant AS (
  SELECT vv.account_id, count(*) AS open_hc
  FROM public.vacancies vv
  WHERE vv.status = 'Open'
    AND vv.deleted_at IS NULL
    AND COALESCE(vv.is_archived, false)       = false
    AND COALESCE(vv.is_pool_vacancy, false)   = false
    AND COALESCE(vv.affects_required_hc, true) = true
  GROUP BY vv.account_id
),
base AS (
  SELECT
    a.id          AS account_id,
    a.account_name,
    a.account_code,
    a.group_id,
    g.group_name,
    g.group_code,
    round(COALESCE(f.filled_hc, 0) + COALESCE(csk.filled_hc, 0), 4)::numeric(12,4) AS filled_hc,
    COALESCE(f.actual_hc, 0)  + COALESCE(csk.actual_hc, 0)                          AS actual_hc,
    (COALESCE(p.pipeline_count, 0) + COALESCE(csk.pipeline_count, 0))::bigint       AS pipeline_count,
    COALESCE(v.open_hc, 0)                                                           AS open_hc,
    round(
      COALESCE(svn.vacant_slots,   0)::numeric
    + COALESCE(svr.vacant_hc,      0)::numeric
    + COALESCE(csk.slot_vacant_hc, 0)::numeric,
    0)::numeric(12,4)                                                                AS slot_vacant_hc,
    round(
      COALESCE(f.filled_hc,          0)
    + COALESCE(csk.filled_hc,        0)
    + COALESCE(p.pipeline_count,     0)
    + COALESCE(csk.pipeline_count,   0)
    + COALESCE(svn.vacant_slots,     0)::numeric
    + COALESCE(svr.vacant_hc,        0)::numeric
    + COALESCE(csk.slot_vacant_hc,   0)::numeric,
    0)::numeric(12,4)                                                                AS required_hc
  FROM public.accounts a
  LEFT JOIN public.groups          g    ON g.id          = a.group_id
  LEFT JOIN filled                 f    ON f.account_id  = a.id
  LEFT JOIN pipeline               p    ON p.account_id  = a.id
  LEFT JOIN coverage_slot_kpi      csk  ON csk.account_id = a.id
  LEFT JOIN vacant                 v    ON v.account_id  = a.id
  LEFT JOIN slot_vacant_non_roving svn  ON svn.account_id = a.id
  LEFT JOIN slot_vacant_roving     svr  ON svr.account_id = a.id
  WHERE a.is_active = true
    AND COALESCE(a.is_pool_account, false) = false
    AND (
         public.i_have_full_access()
      OR a.id = ANY (public.get_my_allowed_account_ids())
    )
)
SELECT
  account_id, account_name, account_code, group_id, group_name, group_code,
  filled_hc,
  actual_hc,
  pipeline_count,
  open_hc,
  required_hc,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(LEAST(1.0, GREATEST(0.0, actual_hc::numeric / required_hc)), 4) END AS mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(LEAST(1.0, GREATEST(0.0, (actual_hc::numeric + pipeline_count) / required_hc)), 4) END AS projected_mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(slot_vacant_hc / required_hc, 4) END                     AS vacancy_rate,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(pipeline_count / required_hc, 4) END                     AS pipeline_coverage,
  CASE WHEN required_hc = 0              THEN 'healthy'::text
       WHEN actual_hc::numeric / required_hc >= 1.0 THEN 'healthy'::text
       WHEN actual_hc::numeric / required_hc >= 0.9 THEN 'at_risk'::text
       ELSE                                   'critical'::text
  END                                                                       AS health_status,
  slot_vacant_hc
FROM base;

ALTER VIEW public.v_account_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_account_allocation_kpi IS
  'Allocation-based per-account KPI. ADR-001 Rule 2 compliant: actual_hc derives strictly from active, non-separated employees in public.plantilla. '
  'OHM2026_1136 §3: pipeline_count reverted to hr_emploc source. '
  'OHM2026_0073: slot_vacant_hc = non-roving COUNT(open,pipeline) + roving 1/N + coverage open. '
  'OHM2026_0079: mfr/projected_mfr return 0.0 when required_hc = 0. '
  'ADR-001 Invariant 17: required_hc and slot_vacant_hc rounded to whole numbers to protect account-level metrics from roving 1/N decimal artifacts.';
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;

-- Recreate dependent CENCOM views
CREATE OR REPLACE VIEW public.v_cencom_account_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT ak.*
FROM   public.v_account_allocation_kpi ak
JOIN   public.groups g ON g.id = ak.group_id
WHERE  g.cencom_scope = true;

ALTER VIEW public.v_cencom_account_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_account_allocation_kpi IS
  'Per-account KPI restricted to CENCOM groups (cencom_scope=true). Inherits ADR-001 Rule 2 active headcount derivation.';
GRANT SELECT ON public.v_cencom_account_allocation_kpi TO authenticated, service_role;

CREATE OR REPLACE VIEW public.v_cencom_group_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT
  group_id, group_name, group_code,
  round(sum(filled_hc), 4)               AS filled_hc,
  sum(actual_hc)::bigint                 AS actual_hc,
  round(sum(pipeline_count), 0)::bigint  AS pipeline_count,
  sum(open_hc)::bigint                   AS open_hc,
  round(sum(required_hc), 4)             AS required_hc,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(filled_hc) / sum(required_hc), 4) END               AS mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round((sum(filled_hc) + sum(pipeline_count)) / sum(required_hc), 4) END AS projected_mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(slot_vacant_hc) / sum(required_hc), 4) END          AS vacancy_rate,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(pipeline_count) / sum(required_hc), 4) END          AS pipeline_coverage,
  CASE WHEN sum(required_hc) = 0                         THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 1.0     THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 0.9     THEN 'at_risk'::text
       ELSE                                                   'critical'::text
  END                                                                      AS health_status,
  round(sum(slot_vacant_hc), 4)          AS slot_vacant_hc
FROM public.v_cencom_account_allocation_kpi
GROUP BY group_id, group_name, group_code;

ALTER VIEW public.v_cencom_group_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_group_allocation_kpi IS
  'Per-group CENCOM KPI. Inherits ADR-001 Rule 2 active headcount derivation.';
GRANT SELECT ON public.v_cencom_group_allocation_kpi TO authenticated, service_role;

CREATE OR REPLACE VIEW public.v_cencom_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT
  round(sum(filled_hc), 4)               AS filled_hc,
  sum(actual_hc)::bigint                 AS actual_hc,
  round(sum(pipeline_count), 0)::bigint  AS pipeline_count,
  sum(open_hc)::bigint                   AS open_hc,
  round(sum(required_hc), 4)             AS required_hc,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(filled_hc) / sum(required_hc), 4) END               AS mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round((sum(filled_hc) + sum(pipeline_count)) / sum(required_hc), 4) END AS projected_mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(slot_vacant_hc) / sum(required_hc), 4) END          AS vacancy_rate,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(pipeline_count) / sum(required_hc), 4) END          AS pipeline_coverage,
  CASE WHEN sum(required_hc) = 0                         THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 1.0     THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 0.9     THEN 'at_risk'::text
       ELSE                                                   'critical'::text
  END                                                                      AS health_status,
  round(sum(slot_vacant_hc), 4)          AS slot_vacant_hc
FROM public.v_cencom_account_allocation_kpi;

ALTER VIEW public.v_cencom_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_allocation_kpi IS
  'Aggregate CENCOM KPI. Inherits ADR-001 Rule 2 active headcount derivation.';
GRANT SELECT ON public.v_cencom_allocation_kpi TO authenticated, service_role;


-- ── §2. Harden fn_trg_plantilla_vacate_slot_on_inactive Trigger ───────────────

CREATE OR REPLACE FUNCTION public.fn_trg_plantilla_vacate_slot_on_inactive()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (NEW.status IN ('Inactive', 'Deactivated')) AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    -- 1. Vacate occupied plantilla slots
    UPDATE public.plantilla_slots
       SET slot_status = 'open',
           current_occupant_plantilla_id = NULL,
           updated_at = now()
     WHERE current_occupant_plantilla_id = NEW.id
       AND slot_status IN ('occupied', 'filled');

    -- 2. Deactivate employee store allocations
    UPDATE public.employee_store_allocations
       SET is_active = false,
           effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
     WHERE (plantilla_id = NEW.id OR (NEW.employee_no IS NOT NULL AND employee_no = NEW.employee_no))
       AND is_active = true;

    -- 3. Release any coverage slots
    UPDATE public.coverage_slots
       SET slot_status = 'open',
           current_occupant_plantilla_id = NULL,
           updated_at = now()
     WHERE current_occupant_plantilla_id = NEW.id
       AND slot_status = 'active';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_plantilla_vacate_slot_on_inactive ON public.plantilla;
CREATE TRIGGER trg_plantilla_vacate_slot_on_inactive
  AFTER UPDATE OF status
  ON public.plantilla
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_plantilla_vacate_slot_on_inactive();


-- ── §3. Harden fn_plantilla_separation_to_vacancy Status Transition Guard ─────

CREATE OR REPLACE FUNCTION public.fn_plantilla_separation_to_vacancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link        RECORD;
  v_vac         public.vacancies%ROWTYPE;
  v_esa         RECORD;
  v_new_link_id uuid;
  v_hc          numeric;
  v_resolved_requirement_id uuid;
  v_link_status text;
  v_link_vcode  text;
BEGIN
  -- Trigger filter logic: include 'Pending Deactivation' in allowed originating status
  IF OLD.status NOT IN ('Active', 'On Leave', 'For Deactivation', 'Pending Deactivation')
    OR NEW.status NOT IN ('Resigned', 'AWOL', 'Endo', 'Terminated', 'Others',
                          'Inactive', 'Floating', 'For Deactivation')
    OR OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Dynamic resolution of position_id if null or invalid
  IF NEW.position_id IS NULL AND NEW.position IS NOT NULL AND btrim(NEW.position) <> '' THEN
    SELECT p.id INTO NEW.position_id
    FROM public.positions p
    WHERE lower(btrim(p.position_name)) = lower(btrim(NEW.position))
    LIMIT 1;
    IF NEW.position_id IS NOT NULL THEN
      UPDATE public.plantilla
         SET position_id = NEW.position_id
       WHERE id = NEW.id;
    END IF;
  END IF;

  IF NEW.position_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = NEW.position_id
  ) THEN
    SELECT p.id INTO NEW.position_id
    FROM public.positions p
    WHERE lower(btrim(p.position_name)) = lower(btrim(NEW.position))
    LIMIT 1;
    IF NEW.position_id IS NOT NULL THEN
      UPDATE public.plantilla
         SET position_id = NEW.position_id
       WHERE id = NEW.id;
    END IF;
  END IF;

  -- 1. Release the Coverage Group slot this employee occupied, if any.
  IF NEW.coverage_slot_id IS NOT NULL THEN
    UPDATE public.coverage_slots
       SET slot_status = 'open',
           current_occupant_plantilla_id = NULL,
           updated_at = NOW()
     WHERE id = NEW.coverage_slot_id
       AND current_occupant_plantilla_id = NEW.id;

    UPDATE public.hr_emploc
       SET deleted_at = NOW()
     WHERE coverage_slot_id = NEW.coverage_slot_id
       AND deleted_at IS NULL
       AND status = 'Moved to Plantilla';

  ELSIF NEW.coverage_group_id IS NOT NULL THEN
    UPDATE public.coverage_slots
       SET slot_status = 'open',
           current_occupant_plantilla_id = NULL,
           updated_at = NOW()
     WHERE coverage_group_id = NEW.coverage_group_id
       AND current_occupant_plantilla_id = NEW.id;

    UPDATE public.hr_emploc
       SET deleted_at = NOW()
     WHERE coverage_group_id = NEW.coverage_group_id
       AND deleted_at IS NULL
       AND status = 'Moved to Plantilla'
       AND coverage_slot_id IN (
         SELECT id FROM public.coverage_slots
          WHERE coverage_group_id = NEW.coverage_group_id
            AND current_occupant_plantilla_id IS NULL
       );
  END IF;

  -- ── Roving employee path ─────────────────────────────────────────────────
  IF COALESCE(NEW.deployment_type, '') = 'Roving' THEN

    v_link_status := CASE
      WHEN lower(COALESCE(NEW.separation_status, '')) IN ('awol','resigned','terminated','end of contract','endo','others')
        THEN 'Resigned'
      ELSE 'Backed Out'
    END;

    IF NEW.coverage_slot_id IS NOT NULL OR NEW.coverage_group_id IS NOT NULL THEN
      UPDATE public.plantilla_store_links
         SET status      = v_link_status,
             unlinked_at = NOW()
       WHERE plantilla_id = NEW.id
         AND status       = 'Active';

      UPDATE public.employee_store_allocations
         SET is_active     = false,
             effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
       WHERE plantilla_id = NEW.id
         AND is_active    = true;

      RETURN NEW;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.plantilla_store_links
       WHERE plantilla_id = NEW.id AND status = 'Active'
    ) THEN
      FOR v_link IN
        SELECT * FROM public.plantilla_store_links
         WHERE plantilla_id = NEW.id AND status = 'Active'
      LOOP
        SELECT COALESCE(esa.filled_hc, 1)::numeric INTO v_hc
          FROM public.employee_store_allocations esa
         WHERE esa.plantilla_id        = NEW.id
           AND esa.vcode               = v_link.vcode
           AND esa.is_active           = true
         LIMIT 1;

        v_hc := COALESCE(v_hc, 1);

        IF v_link.vacancy_id IS NOT NULL THEN
          SELECT * INTO v_vac FROM public.vacancies
           WHERE id = v_link.vacancy_id AND deleted_at IS NULL LIMIT 1;
        ELSE
          SELECT * INTO v_vac FROM public.vacancies
           WHERE vcode = v_link.vcode AND deleted_at IS NULL LIMIT 1;
        END IF;

        IF v_vac.id IS NOT NULL THEN
          IF v_vac.status IN ('Filled', 'Closed') THEN
            UPDATE public.vacancies
               SET status         = 'Open',
                   is_archived    = false,
                   archived_at    = NULL,
                   archived_by    = NULL,
                   required_headcount = GREATEST(
                                         COALESCE(required_headcount, 0) + v_hc,
                                         1
                                       ),
                   updated_at     = NOW()
             WHERE id = v_vac.id;
          ELSE
            UPDATE public.vacancies
               SET required_headcount = GREATEST(
                                         COALESCE(required_headcount, 0) + v_hc,
                                         1
                                       ),
                   updated_at = NOW()
             WHERE id = v_vac.id;
          END IF;
        ELSE
          INSERT INTO public.vacancies (
            vcode, account, account_id, store_id, store_name, position, position_id,
            status, vacancy_type, required_headcount, employment_type,
            source, created_at, updated_at
          )
          SELECT
            v_link.vcode,
            NEW.account,
            NEW.account_id,
            s.id,
            s.store_name,
            COALESCE(p.position_name, NEW.position, 'UNSPECIFIED'),
            p.id,
            'Open',
            'Backfill',
            GREATEST(v_hc, 1),
            'Roving',
            'plantilla',
            NOW(),
            NOW()
          FROM (SELECT 1) dummy
          LEFT JOIN public.positions p ON p.id = NEW.position_id
          LEFT JOIN public.stores s ON s.vcode = v_link.vcode
          RETURNING * INTO v_vac;

          UPDATE public.plantilla_store_links
             SET vacancy_id = v_vac.id
           WHERE id = v_link.id;
        END IF;

        UPDATE public.plantilla_store_links
           SET status      = v_link_status,
               unlinked_at = NOW()
         WHERE id = v_link.id;

        -- Archive previous applicants for this roving slot
        IF v_link.vcode IS NOT NULL THEN
          UPDATE public.applicants
             SET is_archived = true,
                 archived_at = NOW()
            WHERE vacancy_vcode = v_link.vcode
              AND COALESCE(is_archived, false) = false;
        END IF;

      END LOOP;

    ELSE
      FOR v_esa IN
        SELECT * FROM public.employee_store_allocations
         WHERE plantilla_id = NEW.id AND is_active = true
      LOOP
        v_hc := COALESCE(v_esa.filled_hc, 1)::numeric;

        SELECT * INTO v_vac FROM public.vacancies
         WHERE store_id    = v_esa.store_id
           AND account_id  = NEW.account_id
           AND COALESCE(employment_type, '') = 'Roving'
           AND deleted_at  IS NULL
           AND status NOT IN ('Filled', 'Closed', 'Cancelled')
         LIMIT 1;

        IF NOT FOUND THEN
          INSERT INTO public.vacancies (
            vcode, account, account_id, store_id, position, position_id,
            status, vacancy_type, employment_type, required_headcount,
            source, created_at, updated_at
          )
          SELECT
            v_esa.store_id::text,
            NEW.account,
            NEW.account_id,
            v_esa.store_id,
            COALESCE(p.position_name, NEW.position, 'UNSPECIFIED'),
            p.id,
            'Open',
            'Backfill',
            'Roving',
            GREATEST(v_hc, 1),
            'plantilla',
            NOW(),
            NOW()
          FROM (SELECT 1) dummy
          LEFT JOIN public.positions p ON p.id = NEW.position_id
          RETURNING * INTO v_vac;
        ELSE
          UPDATE public.vacancies
             SET required_headcount = GREATEST(
                                       COALESCE(required_headcount, 0) + v_hc,
                                       1
                                     ),
                 status      = 'Open',
                 is_archived = false,
                 archived_at = NULL,
                 archived_by = NULL,
                 updated_at  = NOW()
           WHERE id = v_vac.id
          RETURNING * INTO v_vac;
        END IF;

        v_link_vcode := COALESCE(v_vac.vcode, v_esa.vcode, v_esa.store_id::text);

        INSERT INTO public.plantilla_store_links (
          plantilla_id, account, vcode, store_name, vacancy_id, status
        )
        SELECT NEW.id, NEW.account, v_link_vcode, v_esa.store_name, v_vac.id, v_link_status
         WHERE NOT EXISTS (
           SELECT 1 FROM public.plantilla_store_links psl
            WHERE psl.plantilla_id = NEW.id
              AND psl.vcode        = v_link_vcode
         )
        RETURNING id INTO v_new_link_id;

        IF v_new_link_id IS NOT NULL THEN
          UPDATE public.plantilla_store_links
             SET unlinked_at = NOW()
           WHERE id = (
             SELECT id FROM public.plantilla_store_links
              WHERE plantilla_id = NEW.id
                AND vcode        = v_link_vcode
              ORDER BY created_at DESC
              LIMIT 1
           );
        END IF;

        -- Archive previous applicants for this roving slot
        IF v_link_vcode IS NOT NULL THEN
          UPDATE public.applicants
             SET is_archived = true,
                 archived_at = NOW()
            WHERE vacancy_vcode = v_link_vcode
              AND COALESCE(is_archived, false) = false;
        END IF;

      END LOOP;
    END IF;

    UPDATE public.employee_store_allocations
       SET is_active     = false,
           effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
     WHERE plantilla_id = NEW.id
       AND is_active    = true;

    RETURN NEW;
  END IF;

  -- ── Stationary employee path ─────────────────────────────────────────────
  PERFORM public.reopen_or_create_vacancy_for_plantilla(
    NEW.id,
    NEW.date_of_separation,
    'Backfill'
  );

  UPDATE public.employee_store_allocations
     SET is_active     = false,
         effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
   WHERE plantilla_id = NEW.id
     AND is_active    = true;

  RETURN NEW;
END;
$function$;


-- ── §4. Systematic Data Alignment & Separation Sweep ──────────────────────────

-- Disable trigger guards during data sweep
ALTER TABLE public.plantilla DISABLE TRIGGER trg_plantilla_separation_to_vacancy;
ALTER TABLE public.vacancies DISABLE TRIGGER trg_assert_vacancy_edit_allowed;

-- 1. Transition past/effective separated personnel to 'Inactive'
UPDATE public.plantilla
   SET status = 'Inactive',
       inactive_at = COALESCE(inactive_at, now()),
       updated_at = now()
 WHERE date_of_separation IS NOT NULL
   AND date_of_separation <= CURRENT_DATE
   AND status NOT IN ('Inactive', 'Deactivated');

-- 2. Deactivate employee_store_allocations for inactive, deactivated, or separated personnel
UPDATE public.employee_store_allocations esa
   SET is_active = false,
       effective_end = COALESCE(p.date_of_separation, esa.effective_end, CURRENT_DATE)
  FROM public.plantilla p
 WHERE p.id = esa.plantilla_id
   AND esa.is_active = true
   AND (
     p.status IN ('Inactive', 'Deactivated')
     OR (p.date_of_separation IS NOT NULL AND p.date_of_separation <= CURRENT_DATE)
   );

-- 3. Vacate occupied plantilla_slots for inactive/separated personnel
UPDATE public.plantilla_slots ps
   SET slot_status = 'open',
       current_occupant_plantilla_id = NULL,
       updated_at = now()
  FROM public.plantilla p
 WHERE p.id = ps.current_occupant_plantilla_id
   AND ps.slot_status IN ('occupied', 'filled')
   AND (
     p.status IN ('Inactive', 'Deactivated')
     OR (p.date_of_separation IS NOT NULL AND p.date_of_separation <= CURRENT_DATE)
   );

-- Re-enable trigger guards
ALTER TABLE public.vacancies ENABLE TRIGGER trg_assert_vacancy_edit_allowed;
ALTER TABLE public.plantilla ENABLE TRIGGER trg_plantilla_separation_to_vacancy;

COMMIT;
