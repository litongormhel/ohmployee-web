-- ============================================================
-- OHMployee — Consolidate Candidate Pipeline Stages
-- Prompt ID : ohm#p8r4m2k9
-- Date      : 2026-10-22
-- Scope     : Consolidate progressive pipeline stages to 6 target options:
--             1. For Interview / Intro
--             2. For Requirements
--             3. For Medical
--             4. Pending Approval
--             5. For Deployment
--             6. For Onboard
-- ============================================================

-- §1. Update canonical active applicant predicate
CREATE OR REPLACE FUNCTION public.fn_is_active_vacancy_applicant_status(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT btrim(regexp_replace(lower(COALESCE(p_status, '')), '[^a-z0-9]+', '_', 'g'), '_') IN (
    'new',
    'sourcing',
    'for_sourcing',
    'pooling',
    'contacting_candidate',
    'not_answering',
    'out_of_coverage_area',
    'for_interview',
    'for_interview_intro',
    'for_online_intro',
    'for_face_to_face_intro',
    'done_intro',
    'for_requirements',
    'for_medical',
    'pending_approval',
    'waiting_sco_schedule',
    'waiting_approval',
    'for_deployment',
    'for_onboard',
    'hr_processing'
  );
$$;

COMMENT ON FUNCTION public.fn_is_active_vacancy_applicant_status(text) IS
  'Consolidates active applicant predicate to support For Interview / Intro and Pending Approval alongside existing and legacy stages.';

GRANT EXECUTE ON FUNCTION public.fn_is_active_vacancy_applicant_status(text)
  TO authenticated, service_role, anon;

-- §2. Migrate existing applicant records in public.applicants
-- 1. For Interview, For Online Intro, For Face-to-Face Intro -> For Interview / Intro
UPDATE public.applicants
SET    status     = 'For Interview / Intro',
       updated_at = now()
WHERE  status IN ('For Interview', 'For Online Intro', 'For Face-to-Face Intro')
   OR  lower(btrim(status)) IN ('for interview', 'for online intro', 'for face-to-face intro', 'for_interview', 'for_online_intro', 'for_face_to_face_intro');

-- 2. Done Intro -> For Requirements
UPDATE public.applicants
SET    status     = 'For Requirements',
       updated_at = now()
WHERE  status = 'Done Intro'
   OR  lower(btrim(status)) IN ('done intro', 'done_intro');

-- 3. Waiting SCO Schedule, Waiting Approval, Endorsed to Ops -> Pending Approval
UPDATE public.applicants
SET    status     = 'Pending Approval',
       updated_at = now()
WHERE  status IN ('Waiting SCO Schedule', 'Waiting Approval', 'Endorsed to Ops', 'Endorsed')
   OR  lower(btrim(status)) IN ('waiting sco schedule', 'waiting approval', 'endorsed to ops', 'endorsed', 'waiting_sco_schedule', 'waiting_approval', 'endorsed_to_ops');

-- §3. Prune & update public.applicant_status_options lookup table
-- Deactivate deprecated stages
UPDATE public.applicant_status_options
SET is_active = false,
    updated_at = now()
WHERE status_code IN (
  'for_interview',
  'for_online_intro',
  'for_face_to_face_intro',
  'done_intro',
  'waiting_sco_schedule',
  'waiting_approval',
  'endorsed'
);

-- Upsert the target 6 stages
INSERT INTO public.applicant_status_options
  (status_code, label, is_terminal, allow_on_create, is_system_only, color_key, sort_order, is_active)
VALUES
  ('for_interview_intro', 'For Interview / Intro', false, false, false, 'primary', 30, true),
  ('for_requirements',    'For Requirements',       false, false, false, 'primary', 40, true),
  ('for_medical',         'For Medical',            false, false, false, 'warning', 45, true),
  ('pending_approval',     'Pending Approval',       false, false, false, 'warning', 50, true),
  ('for_deployment',      'For Deployment',         false, false, false, 'info',    55, true),
  ('for_onboard',         'For Onboard',            false, false, false, 'success', 60, true)
ON CONFLICT (status_code) DO UPDATE
  SET label           = EXCLUDED.label,
      is_terminal     = EXCLUDED.is_terminal,
      allow_on_create = EXCLUDED.allow_on_create,
      is_system_only  = EXCLUDED.is_system_only,
      color_key       = EXCLUDED.color_key,
      sort_order      = EXCLUDED.sort_order,
      is_active       = true,
      updated_at      = now();

-- §4. Update public.vw_applicant_funnel view
CREATE OR REPLACE VIEW public.vw_applicant_funnel AS
 SELECT v.account_id,
    a.group_id,
    count(*) FILTER (WHERE (ap.status = ANY (ARRAY['Sourced'::text, 'For Interview'::text, 'For Interview / Intro'::text, 'Hired'::text]))) AS sourced,
    count(*) FILTER (WHERE (ap.status = ANY (ARRAY['Applied'::text, 'For Interview'::text, 'For Interview / Intro'::text, 'Hired'::text]))) AS applied,
    count(*) FILTER (WHERE (ap.status = ANY (ARRAY['Screened'::text, 'For Interview'::text, 'For Interview / Intro'::text, 'Hired'::text]))) AS screened,
    count(*) FILTER (WHERE (ap.status = ANY (ARRAY['For Interview'::text, 'For Interview / Intro'::text, 'Hired'::text]))) AS interview,
    count(*) FILTER (WHERE (ap.status = ANY (ARRAY['Offer'::text, 'Hired'::text]))) AS offer,
    count(*) FILTER (WHERE (ap.status = 'Hired'::text)) AS hired
   FROM ((applicants ap
     JOIN vacancies v ON ((v.vcode = ap.vacancy_vcode)))
     JOIN accounts a ON ((a.id = v.account_id)))
  WHERE (COALESCE(ap.is_archived, false) = false)
  GROUP BY v.account_id, a.group_id;
