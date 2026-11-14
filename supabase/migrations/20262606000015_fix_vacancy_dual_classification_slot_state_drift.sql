-- Prompt ID: ohm#c4a9e2f1
-- Fix: Fix — Vacancy Dual Classification (Open + Closure) via Slot-State Drift (No Regression)
--
-- BUSINESS RULES & OBJECTIVES:
-- 1. Slot closure MUST override ALL states in vw_slot_derived_vacancy_shadow (open_count = 0 when slot is closed).
-- 2. Enforce slot closure sync to vacancies.status via trigger fn_sync_closed_slot_to_vacancy().
-- 3. Allow Filled -> Closed status transition in fn_is_valid_vacancy_transition().
-- 4. Idempotent backfill of historical unarchived vacancies with closed slots.

BEGIN;

-- LAYER 0 — EXTEND VACANCY TRANSITION GUARD (ALLOW FILLED -> CLOSED)

CREATE OR REPLACE FUNCTION public.fn_is_valid_vacancy_transition(p_old text, p_new text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE
    -- NULL/blank old (insert path) → only Draft / Pending Approval / Open allowed at create time
    WHEN p_old IS NULL OR p_old = '' THEN p_new IN ('Draft','Pending Approval','Open')
    WHEN p_old = p_new THEN TRUE
    WHEN p_old = 'Draft'            AND p_new IN ('Pending Approval','Closed','Rejected') THEN TRUE
    WHEN p_old = 'Pending Approval' AND p_new IN ('Open','Rejected','Closed')             THEN TRUE
    WHEN p_old = 'Open'             AND p_new IN ('On Hold','Filled','Closed')             THEN TRUE
    WHEN p_old = 'On Hold'          AND p_new IN ('Open','Closed')                         THEN TRUE
    -- Filled → Open / Closed: allowed for Coverage Group / Slot Closure transitions.
    WHEN p_old = 'Filled'           AND p_new IN ('Open','Closed')                         THEN TRUE
    -- Legacy values: allow same-state and migration to canon.
    WHEN p_old IN ('For Sourcing','Backout') AND p_new IN ('Open','Closed','Filled','On Hold') THEN TRUE
    WHEN p_old = 'Archived'         AND p_new = 'Archived'                                  THEN TRUE
    ELSE FALSE
  END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_is_valid_vacancy_transition(text,text) TO authenticated;


-- LAYER 1 — VIEW CORRECTION (PRIMARY FIX)

CREATE OR REPLACE VIEW public.vw_slot_derived_vacancy_shadow
  WITH (security_invoker = true)
AS
WITH aging_basis AS (
  SELECT DISTINCT ON (sh.slot_id)
    sh.slot_id,
    sh.created_at AS open_episode_start
  FROM public.slot_history sh
  WHERE sh.new_value = 'open'
  ORDER BY sh.slot_id, sh.created_at DESC
),
pending_closure AS (
  SELECT DISTINCT vcr.vacancy_vcode
  FROM public.vacancy_closure_requests vcr
  JOIN public.vacancies v
    ON v.vcode = vcr.vacancy_vcode
   AND v.deleted_at IS NULL
   AND COALESCE(v.is_archived, false) = false
  WHERE vcr.status = 'Pending'
),
applicant_counts AS (
  SELECT
    a.vacancy_vcode,
    COUNT(DISTINCT a.id) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND public.fn_is_active_vacancy_applicant_status(a.status)
    ) AS pipeline_count,
    COUNT(DISTINCT a.id) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND replace(lower(btrim(COALESCE(a.status, ''))), ' ', '_') = 'confirmed_onboard'
    ) AS hired_count
  FROM public.applicants a
  WHERE a.vacancy_vcode IS NOT NULL
  GROUP BY a.vacancy_vcode
),
req_counts AS (
  SELECT
    vr.vacancy_id,
    SUM(vr.hc_needed)::bigint AS req_hc_needed
  FROM public.vacancy_requirements vr
  GROUP BY vr.vacancy_id
)
SELECT
  ps.legacy_vcode,
  ps.legacy_vcode                                              AS vacancy_id,
  v.id                                                          AS legacy_vacancy_id,
  v.store_name,
  v.area_city,
  v.province,
  v.area_name,
  v.required_headcount                                          AS required_headcount,

  (ARRAY_AGG(ps.store_id   ORDER BY ps.created_at, ps.id::text))[1] AS store_id,
  MIN(st.store_branch)                                               AS store_branch,

  (ARRAY_AGG(ps.account_id ORDER BY ps.created_at, ps.id::text))[1] AS account_id,
  MIN(a.account_name)                                                AS account_name,
  (ARRAY_AGG(ps.group_id   ORDER BY ps.created_at, ps.id::text))[1] AS group_id,
  MIN(g.group_name)                                                  AS group_name,

  MIN(ps.position)                                             AS position,
  MIN(ps.employment_type)                                      AS employment_type,
  false                                                        AS is_roving,

  COUNT(*)                                                     AS required_hc,
  COALESCE(rc.req_hc_needed, COUNT(*))                         AS hc_needed,
  COALESCE(MAX(ac.pipeline_count), 0::bigint)                  AS pipeline_count,
  COALESCE(MAX(ac.hired_count), 0::bigint)                     AS hired_count,

  -- open_count: Override to 0 if any slot is closed
  CASE
    WHEN EXISTS (
      SELECT 1 FROM public.plantilla_slots ps_closed
      WHERE ps_closed.legacy_vcode = ps.legacy_vcode
        AND ps_closed.slot_status = 'closed'
    )
    THEN 0::bigint
    ELSE GREATEST(
      0::bigint,
      COALESCE(rc.req_hc_needed, COUNT(*))
      - COALESCE(MAX(ac.hired_count), 0::bigint)
    )
  END                                                          AS open_count,

  COUNT(*) FILTER (WHERE ps.slot_status = 'hr_processing')     AS hr_processing_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'occupied')          AS occupied_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'closed')            AS closed_count,

  COALESCE(MAX(ac.pipeline_count), 0::bigint)                  AS active_applicant_count,
  bool_or(pc.vacancy_vcode IS NOT NULL)                        AS has_pending_closure,

  -- vacancy_tab precedence: Slot closure MUST override ALL states
  CASE
    WHEN bool_or(pc.vacancy_vcode IS NOT NULL)
      OR EXISTS (
        SELECT 1 FROM public.plantilla_slots ps_closed
        WHERE ps_closed.legacy_vcode = ps.legacy_vcode
          AND ps_closed.slot_status = 'closed'
      )
    THEN 'Closure'
    WHEN GREATEST(
      0::bigint,
      COALESCE(rc.req_hc_needed, COUNT(*))
      - COALESCE(MAX(ac.hired_count), 0::bigint)
    ) > 0
    THEN 'Open'
    WHEN COALESCE(MAX(ac.pipeline_count), 0::bigint) > 0 THEN 'Pipeline'
    WHEN COALESCE(MAX(ac.hired_count), 0::bigint) >= COALESCE(rc.req_hc_needed, COUNT(*)) THEN 'Hired'
    ELSE 'Open'
  END                                                          AS vacancy_tab,

  MIN(COALESCE(ab.open_episode_start, ps.created_at))
    FILTER (WHERE ps.slot_status = 'open')                     AS aging_start_at,

  CASE
    WHEN GREATEST(
      0::bigint,
      COALESCE(rc.req_hc_needed, COUNT(*))
      - COALESCE(MAX(ac.hired_count), 0::bigint)
    ) = 0 THEN NULL::integer
    WHEN (MIN(COALESCE(ab.open_episode_start, ps.created_at))
          FILTER (WHERE ps.slot_status = 'open'))::date > CURRENT_DATE
      THEN NULL::integer
    ELSE (
      CURRENT_DATE -
      (MIN(COALESCE(ab.open_episode_start, ps.created_at))
       FILTER (WHERE ps.slot_status = 'open'))::date
    )
  END                                                          AS aging_days,

  MIN(ps.created_at)                                           AS created_at,
  MAX(ps.updated_at)                                           AS updated_at,
  MAX(ps.closed_at)                                            AS closed_at,

  (ARRAY_AGG(ps.source_hc_request_id ORDER BY ps.created_at, ps.id::text))[1] AS source_hc_request_id,

  v.urgency_level,
  v.hrco_name,
  v.hrco_user_id,
  v.target_fill_date,
  v.triggered_by_user_id,
  v.triggered_by_name

FROM public.plantilla_slots ps
LEFT JOIN aging_basis ab ON ab.slot_id = ps.id
LEFT JOIN public.stores st ON st.id = ps.store_id
LEFT JOIN public.accounts a ON a.id = ps.account_id
LEFT JOIN public.groups g ON g.id = ps.group_id
LEFT JOIN pending_closure pc ON pc.vacancy_vcode = ps.legacy_vcode
LEFT JOIN applicant_counts ac ON ac.vacancy_vcode = ps.legacy_vcode
INNER JOIN public.vacancies v
  ON v.vcode = ps.legacy_vcode
 AND v.deleted_at IS NULL
 AND COALESCE(v.is_archived, false) = false
 AND v.status <> 'Archived'
LEFT JOIN req_counts rc ON rc.vacancy_id = v.id
WHERE ps.legacy_vcode IS NOT NULL
  AND ps.is_roving = false
  AND NOT EXISTS (
    SELECT 1
    FROM public.coverage_group_stores cgs
    JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
    WHERE cgs.store_id = ps.store_id
      AND cgs.archived_at IS NULL
      AND cg.archived_at IS NULL
  )
GROUP BY ps.legacy_vcode, v.id, rc.req_hc_needed;

COMMENT ON VIEW public.vw_slot_derived_vacancy_shadow IS
  'Slot-derived Vacancy read model. Single HC source: SUM(vacancy_requirements.hc_needed). open_count = 0 when slot is closed. Prompt: ohm#c4a9e2f1.';


-- LAYER 2 — DATA INTEGRITY GUARD (PREVENT FUTURE DRIFT)

CREATE OR REPLACE FUNCTION public.fn_sync_closed_slot_to_vacancy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.slot_status = 'closed' AND (TG_OP = 'INSERT' OR OLD.slot_status IS DISTINCT FROM NEW.slot_status) THEN
    IF NEW.legacy_vcode IS NOT NULL THEN
      UPDATE public.vacancies
      SET status = 'Closed',
          updated_at = NOW()
      WHERE vcode = NEW.legacy_vcode
        AND status NOT IN ('Closed', 'Archived')
        AND COALESCE(is_archived, false) = false;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_closed_slot_to_vacancy ON public.plantilla_slots;
CREATE TRIGGER trg_sync_closed_slot_to_vacancy
AFTER INSERT OR UPDATE OF slot_status ON public.plantilla_slots
FOR EACH ROW
WHEN (NEW.slot_status = 'closed')
EXECUTE FUNCTION public.fn_sync_closed_slot_to_vacancy();

-- LAYER 2 BACKFILL — Sync historical active unarchived vacancies whose slots are closed
UPDATE public.vacancies v
SET status = 'Closed',
    updated_at = NOW()
WHERE v.status NOT IN ('Closed', 'Archived')
  AND COALESCE(v.is_archived, false) = false
  AND EXISTS (
    SELECT 1 FROM public.plantilla_slots ps
    WHERE ps.legacy_vcode = v.vcode
      AND ps.slot_status = 'closed'
  );

COMMIT;
