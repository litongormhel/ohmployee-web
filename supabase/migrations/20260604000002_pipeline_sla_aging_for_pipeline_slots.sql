-- OHM2026_0073 — Fix: Pipeline cards show no SLA chip
-- ─────────────────────────────────────────────────────────────────────────────
-- Root cause:
--   vw_slot_derived_vacancy_shadow.aging_start_at (mapped to VacancyItem.vacantDate
--   in _mapVacancy via `item['vacant_date'] ?? item['aging_start_at']`) is computed
--   with FILTER (WHERE ps.slot_status = 'open'). A VCODE whose slots are all in
--   'pipeline' status (i.e. an applicant is bound to every slot, so the card lands
--   in the Pipeline tab) has zero 'open' slots, so the FILTER returns NULL.
--   Flutter's SlaChip only renders when _computeAgingDays(vacantDate) != null, so
--   the Pipeline card shows no SLA, while Open cards (which have open slots) do.
--
-- Fix:
--   aging_start_at falls back to the oldest open-episode start among 'pipeline'
--   slots when no 'open' slots exist. open_episode_start is the timestamp the slot
--   last transitioned INTO 'open' (from slot_history) — i.e. the date the slot
--   became vacant, the same semantic as the Open tab. This is NOT the pipeline
--   entry date / applicant status date. For mixed VCODEs (some open + some
--   pipeline slots) the COALESCE returns the open-slot value first, so Open tab
--   SLA is byte-for-byte unchanged.
--
-- Scope: redefine vw_slot_derived_vacancy_shadow only. Column list, order, types,
--   security_invoker, and grants are unchanged → CREATE OR REPLACE is safe and
--   preserves existing GRANTs. The slot-grain detail view is untouched.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW public.vw_slot_derived_vacancy_shadow
  WITH (security_invoker = true)
AS
WITH aging_basis AS (
  -- Most recent transition INTO 'open' per slot = start of current open episode.
  SELECT DISTINCT ON (sh.slot_id)
    sh.slot_id,
    sh.created_at AS open_episode_start
  FROM public.slot_history sh
  WHERE sh.new_value = 'open'
  ORDER BY sh.slot_id, sh.created_at DESC
),
pending_closure AS (
  -- VCODEs with an active Pending closure request (VCODE-level override, Q8).
  SELECT DISTINCT vcr.vacancy_vcode
  FROM public.vacancy_closure_requests vcr
  WHERE vcr.status = 'Pending'
)
SELECT
  -- ── VCODE key (grain) ─────────────────────────────────────────────────────
  ps.legacy_vcode,

  -- ── Identity — authoritative per-VCODE fields from vacancies ─────────────
  v.id                                                          AS legacy_vacancy_id,
  v.store_name,
  v.area_city,
  v.province,
  v.area_name,

  v.is_archived,

  -- ── Store detail (constant per VCODE; roving excluded in WHERE) ───────────
  (ARRAY_AGG(ps.store_id   ORDER BY ps.created_at, ps.id::text))[1] AS store_id,
  MIN(st.store_branch)                                               AS store_branch,

  -- ── Org scope (constant per VCODE) ───────────────────────────────────────
  (ARRAY_AGG(ps.account_id ORDER BY ps.created_at, ps.id::text))[1] AS account_id,
  MIN(a.account_name)                                                AS account_name,
  (ARRAY_AGG(ps.group_id   ORDER BY ps.created_at, ps.id::text))[1] AS group_id,
  MIN(g.group_name)                                                  AS group_name,

  -- ── Position definition (constant per VCODE) ─────────────────────────────
  MIN(ps.position)                                              AS position,
  MIN(ps.employment_type)                                       AS employment_type,
  false                                                         AS is_roving,

  -- ── HC counts (Q3 aggregation table) ─────────────────────────────────────
  COUNT(*)                                                      AS required_hc,
  COUNT(*) FILTER (WHERE ps.slot_status = 'open')               AS open_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline')           AS pipeline_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'hr_processing')      AS hr_processing_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'occupied')           AS occupied_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'closed')             AS closed_count,

  -- active_applicant_count = pipeline_count (Phase B one-active-per-slot invariant).
  COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline')           AS active_applicant_count,

  -- ── Pending closure flag (VCODE-level) ───────────────────────────────────
  bool_or(pc.vacancy_vcode IS NOT NULL)                         AS has_pending_closure,

  -- ── Vacancy tab — Q4 priority (exactly one tab per VCODE) ────────────────
  CASE
    WHEN bool_or(pc.vacancy_vcode IS NOT NULL)
      THEN 'Closure'
    WHEN COUNT(*) FILTER (WHERE ps.slot_status = 'open') > 0
      THEN 'Open'
    WHEN COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline') > 0
      THEN 'Pipeline'
    WHEN COUNT(*) FILTER (WHERE ps.slot_status = 'closed') = COUNT(*)
         AND COUNT(*) > 0
      THEN 'Closure'
    ELSE NULL
  END                                                           AS vacancy_tab,

  -- ── Aging — oldest open-episode start (Q7) ───────────────────────────────
  -- OHM2026_0073: prefer open slots (Open tab, unchanged), fall back to the
  -- oldest open-episode start among pipeline slots so Pipeline-only VCODEs still
  -- expose a vacant_date and render the SLA chip. open_episode_start is the date
  -- the slot became vacant (transition INTO 'open'), NOT the pipeline entry date.
  COALESCE(
    MIN(COALESCE(ab.open_episode_start, ps.created_at))
      FILTER (WHERE ps.slot_status = 'open'),
    MIN(COALESCE(ab.open_episode_start, ps.created_at))
      FILTER (WHERE ps.slot_status = 'pipeline')
  )                                                             AS aging_start_at,

  CASE
    WHEN COUNT(*) FILTER (WHERE ps.slot_status IN ('open', 'pipeline')) = 0
      THEN NULL::integer
    WHEN (COALESCE(
            MIN(COALESCE(ab.open_episode_start, ps.created_at))
              FILTER (WHERE ps.slot_status = 'open'),
            MIN(COALESCE(ab.open_episode_start, ps.created_at))
              FILTER (WHERE ps.slot_status = 'pipeline')
          ))::date > CURRENT_DATE
      THEN NULL::integer
    ELSE
      (CURRENT_DATE -
       (COALESCE(
          MIN(COALESCE(ab.open_episode_start, ps.created_at))
            FILTER (WHERE ps.slot_status = 'open'),
          MIN(COALESCE(ab.open_episode_start, ps.created_at))
            FILTER (WHERE ps.slot_status = 'pipeline')
        ))::date
      )
  END                                                           AS aging_days,

  -- ── Timestamps ────────────────────────────────────────────────────────────
  MIN(ps.created_at)                                            AS created_at,
  MAX(ps.updated_at)                                            AS updated_at,
  MAX(ps.closed_at)                                             AS closed_at,

  -- ── HC request seed ───────────────────────────────────────────────────────
  (ARRAY_AGG(ps.source_hc_request_id ORDER BY ps.created_at, ps.id::text))[1] AS source_hc_request_id,

  -- ── Legacy vacancy snapshot fields (parity with vw_vacancy_list) ─────────
  v.urgency_level,
  v.hrco_name,
  v.hrco_user_id,
  v.target_fill_date,
  v.triggered_by_user_id,
  v.triggered_by_name

FROM public.plantilla_slots ps

LEFT JOIN aging_basis ab
  ON ab.slot_id = ps.id

LEFT JOIN public.stores st
  ON st.id = ps.store_id

LEFT JOIN public.accounts a
  ON a.id = ps.account_id

LEFT JOIN public.groups g
  ON g.id = ps.group_id

LEFT JOIN pending_closure pc
  ON pc.vacancy_vcode = ps.legacy_vcode

INNER JOIN public.vacancies v
  ON v.vcode = ps.legacy_vcode
  AND v.deleted_at IS NULL
  AND COALESCE(v.is_archived, false) = false

WHERE ps.legacy_vcode IS NOT NULL
  AND ps.is_roving = false

GROUP BY
  ps.legacy_vcode,
  v.id;

COMMENT ON VIEW public.vw_slot_derived_vacancy_shadow IS
  'SHADOW VIEW — OHM2026_0073 (pipeline SLA fix on top of OHM2026_0070). '
  'VCODE-grain: 1 row = 1 legacy_vcode / vacancy card. '
  'aging_start_at = oldest open-episode start among open slots, falling back to '
  'pipeline slots so Pipeline-only VCODEs expose vacant_date for the SLA chip. '
  'Open tab aging unchanged (COALESCE prefers open-slot value). '
  'SECURITY INVOKER — inherits caller RLS via plantilla_slots_read_scoped policy.';
