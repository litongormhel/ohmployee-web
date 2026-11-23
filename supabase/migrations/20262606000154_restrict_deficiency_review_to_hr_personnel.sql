-- ═══════════════════════════════════════════════════════════════════════════
-- Migration: 20262606000154_restrict_deficiency_review_to_hr_personnel.sql
-- Description: Restrict HR Emploc Deficiency Reviews strictly to Super Admin (100)
--              and HR Personnel (25). Deny Ops team (OM 70, HRCO 45, ATL 42, TL 41).
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Synchronize authoritative compatibility table (role_permission_definitions_compat)
INSERT INTO public.role_permission_definitions_compat (module, action_item, role_level, allowed)
VALUES
  -- Approve Deficiency Correction Review (SA 100 & HR Personnel 25 only)
  ('HR Emploc', 'Approve Deficiency Correction Review', 100, true),
  ('HR Emploc', 'Approve Deficiency Correction Review', 90, false),
  ('HR Emploc', 'Approve Deficiency Correction Review', 70, false),
  ('HR Emploc', 'Approve Deficiency Correction Review', 45, false),
  ('HR Emploc', 'Approve Deficiency Correction Review', 42, false),
  ('HR Emploc', 'Approve Deficiency Correction Review', 41, false),
  ('HR Emploc', 'Approve Deficiency Correction Review', 30, false),
  ('HR Emploc', 'Approve Deficiency Correction Review', 25, true),
  ('HR Emploc', 'Approve Deficiency Correction Review', 20, false),
  ('HR Emploc', 'Approve Deficiency Correction Review', 15, false),
  ('HR Emploc', 'Approve Deficiency Correction Review', 10, false),

  -- Revert / Reject Deficiency Correction Review (SA 100 & HR Personnel 25 only)
  ('HR Emploc', 'Revert / Reject Deficiency Correction Review', 100, true),
  ('HR Emploc', 'Revert / Reject Deficiency Correction Review', 90, false),
  ('HR Emploc', 'Revert / Reject Deficiency Correction Review', 70, false),
  ('HR Emploc', 'Revert / Reject Deficiency Correction Review', 45, false),
  ('HR Emploc', 'Revert / Reject Deficiency Correction Review', 42, false),
  ('HR Emploc', 'Revert / Reject Deficiency Correction Review', 41, false),
  ('HR Emploc', 'Revert / Reject Deficiency Correction Review', 30, false),
  ('HR Emploc', 'Revert / Reject Deficiency Correction Review', 25, true),
  ('HR Emploc', 'Revert / Reject Deficiency Correction Review', 20, false),
  ('HR Emploc', 'Revert / Reject Deficiency Correction Review', 15, false),
  ('HR Emploc', 'Revert / Reject Deficiency Correction Review', 10, false)
ON CONFLICT (module, action_item, role_level)
DO UPDATE SET allowed = EXCLUDED.allowed, updated_at = now();

-- 2. Synchronize base matrix table (role_permission_matrix)
INSERT INTO public.role_permission_matrix (role_id, permission_definition_id, is_allowed, source_type)
SELECT r.id, d.id, v.is_allowed, 'rpc_guard'
FROM (
  VALUES
    -- Approve Deficiency Correction Review
    ('Super Admin',            'hr_emploc', 'deficiency', 'approve_correction', true),
    ('Head Admin',             'hr_emploc', 'deficiency', 'approve_correction', false),
    ('Operations Manager',     'hr_emploc', 'deficiency', 'approve_correction', false),
    ('OM',                     'hr_emploc', 'deficiency', 'approve_correction', false),
    ('HR Coordinator',         'hr_emploc', 'deficiency', 'approve_correction', false),
    ('HRCO',                   'hr_emploc', 'deficiency', 'approve_correction', false),
    ('Assistant Team Leader',  'hr_emploc', 'deficiency', 'approve_correction', false),
    ('ATL',                    'hr_emploc', 'deficiency', 'approve_correction', false),
    ('Team Leader',            'hr_emploc', 'deficiency', 'approve_correction', false),
    ('TL',                     'hr_emploc', 'deficiency', 'approve_correction', false),
    ('ATL/TL',                 'hr_emploc', 'deficiency', 'approve_correction', false),
    ('Encoder',                'hr_emploc', 'deficiency', 'approve_correction', false),
    ('HR Personnel',           'hr_emploc', 'deficiency', 'approve_correction', true),
    ('Recruitment Specialist', 'hr_emploc', 'deficiency', 'approve_correction', false),
    ('Recruitment',            'hr_emploc', 'deficiency', 'approve_correction', false),
    ('Backoffice Personnel',   'hr_emploc', 'deficiency', 'approve_correction', false),
    ('Viewer',                 'hr_emploc', 'deficiency', 'approve_correction', false),

    -- Revert / Reject Deficiency Correction Review
    ('Super Admin',            'hr_emploc', 'deficiency', 'reject_correction', true),
    ('Head Admin',             'hr_emploc', 'deficiency', 'reject_correction', false),
    ('Operations Manager',     'hr_emploc', 'deficiency', 'reject_correction', false),
    ('OM',                     'hr_emploc', 'deficiency', 'reject_correction', false),
    ('HR Coordinator',         'hr_emploc', 'deficiency', 'reject_correction', false),
    ('HRCO',                   'hr_emploc', 'deficiency', 'reject_correction', false),
    ('Assistant Team Leader',  'hr_emploc', 'deficiency', 'reject_correction', false),
    ('ATL',                    'hr_emploc', 'deficiency', 'reject_correction', false),
    ('Team Leader',            'hr_emploc', 'deficiency', 'reject_correction', false),
    ('TL',                     'hr_emploc', 'deficiency', 'reject_correction', false),
    ('ATL/TL',                 'hr_emploc', 'deficiency', 'reject_correction', false),
    ('Encoder',                'hr_emploc', 'deficiency', 'reject_correction', false),
    ('HR Personnel',           'hr_emploc', 'deficiency', 'reject_correction', true),
    ('Recruitment Specialist', 'hr_emploc', 'deficiency', 'reject_correction', false),
    ('Recruitment',            'hr_emploc', 'deficiency', 'reject_correction', false),
    ('Backoffice Personnel',   'hr_emploc', 'deficiency', 'reject_correction', false),
    ('Viewer',                 'hr_emploc', 'deficiency', 'reject_correction', false)
) AS v(role_name, module_key, resource_key, action_key, is_allowed)
JOIN public.roles r ON r.role_name = v.role_name
JOIN public.role_permission_definitions d ON d.module_key = v.module_key AND d.resource_key = v.resource_key AND d.action_key = v.action_key
ON CONFLICT (role_id, permission_definition_id)
DO UPDATE SET is_allowed = EXCLUDED.is_allowed, updated_at = now();
