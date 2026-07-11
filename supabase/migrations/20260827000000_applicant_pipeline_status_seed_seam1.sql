-- ============================================================
-- OHMployee — Applicant Pipeline Status Seed — SEAM 1
-- Prompt ID : OHM2026_0092
-- Date      : 2026-06-01
-- Scope     : Status seed, label patch (new → Sourcing),
--             active-status predicate expansion.
--             No Flutter changes. No remarks/history columns.
--             No new RPCs. No slot/CGCODE architecture changes.
-- ============================================================
-- What this migration does:
--   §1  Expand fn_is_active_vacancy_applicant_status to all 15
--       active status codes (expanded from 4).
--   §2  Patch label 'New' → 'Sourcing' for status_code = 'new'.
--   §3  Sort-order corrections for existing rows to match the
--       canonical 24-status table (makes room for new statuses).
--   §4  Assert is_system_only = true for the 5 system-only
--       statuses (idempotent safety guard).
--   §5  Seed 12 new status rows.
--   §6  Backfill applicants.status label 'New'/'new' → 'Sourcing'.
--   §7  Validation queries (commented out — run in SQL Editor).
--
-- Dependencies (all must be applied before this migration):
--   20260520700000_applicant_backend_infra.sql
--   20260521062542_restore_fn_is_active_vacancy_applicant_status.sql
--   20260521110000_fix_active_applicant_occupancy.sql
--   20260521950000_fix_fn_get_applicant_status_options_overload.sql
--   20260616000000_restore_fn_is_active_vacancy_applicant_status.sql
--
-- Views that depend on fn_is_active_vacancy_applicant_status:
--   vw_vacancy_list, vw_vacancy_detail, v_vacancy_pipeline_status
--   and coverage group shadow views — all call the function by name
--   and will automatically use the updated predicate. No view
--   recreation is required.
--
-- Terminal statuses confirmed unmodified by this migration:
--   confirmed_onboard, did_not_report, rejected_by_ops,
--   backout, rejected, failed, transferred, closed (new seed)
-- ============================================================


-- ============================================================
-- §1  EXPAND fn_is_active_vacancy_applicant_status
--
--     This function is the single source of truth for "is this
--     applicant status counted toward slot occupancy and pipeline
--     active_applicant_count?". It is evaluated at INSERT/UPDATE
--     time by uq_applicants_one_active_per_vcode (partial unique
--     index) and at query time by all pipeline count views.
--
--     Updated FIRST (before data changes) so the unique index
--     enforces the expanded active-status set from the moment
--     new rows with new status codes can be inserted.
--
--     Normalization used by this function:
--       replace(lower(btrim(COALESCE(p_status,''))), ' ', '_')
--     This maps stored LABEL values to matchable tokens. The
--     function must cover both label form and status_code form
--     for any status where the two differ after normalization.
--
--     Status-code 'new' / label 'Sourcing' both covered:
--       'New'     → 'new'      (legacy rows before §6 backfill)
--       'Sourcing'→ 'sourcing' (rows after §6 backfill)
--
--     Status-code 'for_face_to_face_intro' / label 'For Face-to-Face Intro':
--       'For Face-to-Face Intro' → 'for_face-to-face_intro' (hyphens preserved)
--       'for_face_to_face_intro' → 'for_face_to_face_intro' (code form)
--       Both entries included for safety.
--
--     Excluded (NOT active — do not count toward slot occupancy):
--       endorsed           (system-lock, awaiting ops confirmation)
--       confirmed_onboard  (system-lock / pipeline exit point)
--       backout, rejected, failed, closed,
--       did_not_report, rejected_by_ops, transferred  (all terminal)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_is_active_vacancy_applicant_status(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT replace(lower(btrim(COALESCE(p_status, ''))), ' ', '_') IN (
    -- status_code='new': both label forms for transition-period safety
    'sourcing',                  -- label after §6 backfill
    'new',                       -- legacy label / code value (pre-backfill rows)
    -- newly seeded active statuses
    'pooling',
    'contacting_candidate',
    'not_answering',
    'out_of_coverage_area',
    -- existing active statuses (sort order updated in §3)
    'for_interview',
    -- newly seeded
    'for_online_intro',
    'for_face-to-face_intro',    -- normalized from label 'For Face-to-Face Intro'
    'for_face_to_face_intro',    -- status_code form safety alias
    'done_intro',
    -- existing
    'for_requirements',
    -- newly seeded
    'for_medical',
    'waiting_sco_schedule',
    'waiting_approval',
    'for_deployment',
    -- existing
    'for_onboard'
  );
$$;

COMMENT ON FUNCTION public.fn_is_active_vacancy_applicant_status(text) IS
  'OHM2026_0092 SEAM 1 — Canonical active-applicant slot occupancy predicate. '
  'Active = counts toward uq_applicants_one_active_per_vcode and pipeline counts. '
  '15 active status codes: new/sourcing (both label forms), pooling, '
  'contacting_candidate, not_answering, out_of_coverage_area, for_interview, '
  'for_online_intro, for_face_to_face_intro (both normalizations), done_intro, '
  'for_requirements, for_medical, waiting_sco_schedule, waiting_approval, '
  'for_deployment, for_onboard. '
  'Excluded: endorsed, confirmed_onboard (system-lock); '
  'backout, rejected, failed, closed, did_not_report, rejected_by_ops, '
  'transferred (terminal).';

GRANT EXECUTE ON FUNCTION public.fn_is_active_vacancy_applicant_status(text)
  TO authenticated, service_role;


-- ============================================================
-- §2  LABEL PATCH: status_code 'new' → label 'Sourcing'
--
--     DB code 'new' is NOT renamed. Only the display label and
--     allow_on_create flag are updated to match the canonical
--     table. Existing applicants.status rows storing 'New' are
--     backfilled separately in §6.
-- ============================================================
UPDATE public.applicant_status_options
SET    label           = 'Sourcing',
       allow_on_create = true,
       updated_at      = now()
WHERE  status_code = 'new'
  AND  (label <> 'Sourcing' OR allow_on_create = false);


-- ============================================================
-- §3  SORT ORDER CORRECTIONS FOR EXISTING ROWS
--
--     The canonical 24-status table defines new sort positions
--     to accommodate 12 new statuses inserted between existing
--     ones. This update adjusts existing row sort_order values
--     so the full list renders in the correct order.
--
--     Canonical sort positions from OHM2026_0091A §1:
--       new              → 10  (unchanged)
--       for_interview    → 30  (was 20)
--       for_requirements → 45  (was 30)
--       for_onboard      → 58  (was 40)
--       endorsed         → 60  (was 45)
--       confirmed_onboard→ 65  (was 48)
--       backout          → 70  (was 50)
--       rejected         → 75  (was 60)
--       transferred      → 95  (was 70)
--       failed           → 80  (unchanged)
--       did_not_report   → 90  (unchanged)
--       rejected_by_ops  → 92  (was 95)
-- ============================================================
UPDATE public.applicant_status_options
SET sort_order = CASE status_code
  WHEN 'for_interview'     THEN 30
  WHEN 'for_requirements'  THEN 45
  WHEN 'for_onboard'       THEN 58
  WHEN 'endorsed'          THEN 60
  WHEN 'confirmed_onboard' THEN 65
  WHEN 'backout'           THEN 70
  WHEN 'rejected'          THEN 75
  WHEN 'transferred'       THEN 95
  WHEN 'rejected_by_ops'   THEN 92
  ELSE sort_order
END,
updated_at = now()
WHERE status_code IN (
  'for_interview', 'for_requirements', 'for_onboard',
  'endorsed', 'confirmed_onboard', 'backout',
  'rejected', 'transferred', 'rejected_by_ops'
);


-- ============================================================
-- §4  ASSERT is_system_only = true (idempotent safety guard)
--
--     These statuses must never appear in a manual status
--     dropdown. Guarding here is defensive — migrations
--     20260521950000 and 20260616000000 already set these
--     flags, but this ensures the constraint holds regardless
--     of apply order.
-- ============================================================
UPDATE public.applicant_status_options
SET    is_system_only = true,
       updated_at     = now()
WHERE  status_code IN (
         'endorsed',
         'confirmed_onboard',
         'transferred',
         'did_not_report',
         'rejected_by_ops'
       )
  AND  is_system_only = false;


-- ============================================================
-- §5  SEED 12 NEW STATUS ROWS
--
--     These status codes are new additions from OHM2026_0091A.
--     None existed in the original seed.
--
--     ON CONFLICT (status_code) DO UPDATE ensures canonical
--     values are enforced even on repeated migration runs or
--     if a row was manually inserted with different flags.
--
--     New rows are all:
--       is_active = true (default), is_terminal = false (unless noted)
--       allow_on_create = false (only 'new' can be set on create)
--       is_system_only = false (manual statuses)
--
--     'closed' is terminal (manual close, no further workflow).
-- ============================================================
INSERT INTO public.applicant_status_options
  (status_code, label, is_terminal, allow_on_create, is_system_only, color_key, sort_order)
VALUES
  -- Active pipeline statuses (non-terminal, non-system-only)
  ('pooling',               'Pooling',                 false, false, false, 'info',    15),
  ('contacting_candidate',  'Contacting Candidate',    false, false, false, 'info',    20),
  ('not_answering',         'Not Answering',            false, false, false, 'warning', 25),
  ('out_of_coverage_area',  'Out of Coverage Area',    false, false, false, 'warning', 28),
  ('for_online_intro',      'For Online Intro',        false, false, false, 'primary', 35),
  ('for_face_to_face_intro','For Face-to-Face Intro',  false, false, false, 'primary', 38),
  ('done_intro',            'Done Intro',              false, false, false, 'success', 40),
  ('for_medical',           'For Medical',             false, false, false, 'warning', 48),
  ('waiting_sco_schedule',  'Waiting SCO Schedule',    false, false, false, 'warning', 50),
  ('waiting_approval',      'Waiting Approval',        false, false, false, 'warning', 53),
  ('for_deployment',        'For Deployment',          false, false, false, 'info',    55),
  -- Terminal manual-close status
  ('closed',                'Closed',                  true,  false, false, 'neutral', 85)
ON CONFLICT (status_code) DO UPDATE
  SET label           = EXCLUDED.label,
      is_terminal     = EXCLUDED.is_terminal,
      allow_on_create = EXCLUDED.allow_on_create,
      is_system_only  = EXCLUDED.is_system_only,
      color_key       = EXCLUDED.color_key,
      sort_order      = EXCLUDED.sort_order,
      updated_at      = now();


-- ============================================================
-- §6  BACKFILL applicants.status LABEL 'New'/'new' → 'Sourcing'
--
--     applicants.status stores the display label, not the
--     status_code. After patching label in §2, any existing
--     rows still storing 'New' (or the code value 'new') are
--     stale. This backfill aligns them with the new label.
--
--     'new' (lowercase code value) is included defensively —
--     some legacy rows may have stored the code rather than
--     the display label.
--
--     No status_code in applicants is changed — only the
--     label-value stored in applicants.status.
-- ============================================================
UPDATE public.applicants
SET    status     = 'Sourcing',
       updated_at = now()
WHERE  status IN ('New', 'new')
  AND  COALESCE(is_archived, false) = false;


-- ============================================================
-- §7  VALIDATION QUERIES
--     Run in Supabase SQL Editor after applying this migration.
-- ============================================================

-- V1: All 24 canonical status codes exist
-- SELECT status_code, label, is_terminal, is_system_only, allow_on_create,
--        color_key, sort_order
-- FROM   public.applicant_status_options
-- ORDER  BY sort_order;
-- Expected: 24 rows (12 existing + 12 new), ordered correctly.

-- V2: status_code='new' has label='Sourcing' and allow_on_create=true
-- SELECT status_code, label, allow_on_create
-- FROM   public.applicant_status_options
-- WHERE  status_code = 'new';
-- Expected: 1 row — label='Sourcing', allow_on_create=true

-- V3: Active predicate covers all 15 active statuses
-- SELECT
--   s.status_code,
--   s.label,
--   public.fn_is_active_vacancy_applicant_status(s.label) AS is_active_by_label,
--   public.fn_is_active_vacancy_applicant_status(s.status_code) AS is_active_by_code
-- FROM public.applicant_status_options s
-- WHERE s.is_terminal = false
--   AND s.is_system_only = false
-- ORDER BY s.sort_order;
-- Expected: all 15 non-terminal, non-system-only rows return true for both columns.

-- V4: Terminal statuses return false from active predicate
-- SELECT
--   s.status_code,
--   s.label,
--   public.fn_is_active_vacancy_applicant_status(s.label) AS is_active
-- FROM public.applicant_status_options s
-- WHERE s.status_code IN (
--   'confirmed_onboard', 'did_not_report', 'rejected_by_ops',
--   'backout', 'rejected', 'failed', 'transferred', 'closed'
-- )
-- ORDER BY s.sort_order;
-- Expected: all 8 rows return is_active = false.

-- V5: Active predicate returns false for endorsed (system-lock, not active)
-- SELECT public.fn_is_active_vacancy_applicant_status('Endorsed to Ops') AS should_be_false;
-- Expected: false

-- V6: Active predicate returns true for 'Sourcing' (post-backfill label)
-- SELECT public.fn_is_active_vacancy_applicant_status('Sourcing') AS should_be_true;
-- Expected: true

-- V7: Active predicate returns true for 'New' (pre-backfill legacy label)
-- SELECT public.fn_is_active_vacancy_applicant_status('New') AS should_be_true;
-- Expected: true

-- V8: No existing applicants now have status='New' (backfill verification)
-- SELECT COUNT(*) AS remaining_new_label
-- FROM   public.applicants
-- WHERE  status IN ('New', 'new')
--   AND  COALESCE(is_archived, false) = false;
-- Expected: 0

-- V9: Applicants previously 'New' now have status='Sourcing'
-- SELECT COUNT(*) AS sourcing_count
-- FROM   public.applicants
-- WHERE  status = 'Sourcing'
--   AND  COALESCE(is_archived, false) = false;
-- Expected: >= 0 (count of formerly 'New' applicants now showing 'Sourcing')

-- V10: System-only flags correct for 5 system-only statuses
-- SELECT status_code, is_system_only
-- FROM   public.applicant_status_options
-- WHERE  status_code IN (
--   'endorsed', 'confirmed_onboard', 'transferred',
--   'did_not_report', 'rejected_by_ops'
-- )
-- ORDER  BY status_code;
-- Expected: all 5 rows return is_system_only = true

-- V11: fn_get_applicant_status_options returns correct count
-- SELECT jsonb_array_length(public.fn_get_applicant_status_options(false, false)) AS active_total;
-- Expected: 24 (all active statuses, including system-only)
-- SELECT jsonb_array_length(public.fn_get_applicant_status_options(false, true)) AS manual_total;
-- Expected: 19 (24 minus 5 system-only: endorsed, confirmed_onboard, transferred,
--              did_not_report, rejected_by_ops)

-- V12: No duplicate active applicants per vcode introduced by expanded predicate
-- SELECT vacancy_vcode, COUNT(*) AS active_count
-- FROM   public.applicants
-- WHERE  COALESCE(is_archived, false) = false
--   AND  public.fn_is_active_vacancy_applicant_status(status)
-- GROUP  BY vacancy_vcode
-- HAVING COUNT(*) > 1;
-- Expected: 0 rows (uq_applicants_one_active_per_vcode must remain intact)

-- V13: status_code='new' still exists (not renamed)
-- SELECT status_code FROM public.applicant_status_options WHERE status_code = 'new';
-- Expected: 1 row

-- V14: Newly seeded statuses are not is_terminal (except 'closed')
-- SELECT status_code, is_terminal
-- FROM   public.applicant_status_options
-- WHERE  status_code IN (
--   'pooling', 'contacting_candidate', 'not_answering', 'out_of_coverage_area',
--   'for_online_intro', 'for_face_to_face_intro', 'done_intro', 'for_medical',
--   'waiting_sco_schedule', 'waiting_approval', 'for_deployment', 'closed'
-- )
-- ORDER  BY sort_order;
-- Expected: 11 rows with is_terminal=false; 'closed' row with is_terminal=true
