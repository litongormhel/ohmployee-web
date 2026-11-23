-- ═══════════════════════════════════════════════════════════════════════════
-- Migration: 20262606000153_align_data_team_rbac_permissions.sql
-- Description: Align Data Team (Head Admin 90 & Encoder 30) RBAC permissions:
--              1. HR Emploc: Approve Deficiency Correction Review -> Denied for HA (90) & Encoder (30)
--              2. HR Emploc: Revert / Reject Deficiency Correction Review -> Denied for HA (90) & Encoder (30)
--              3. Plantilla: Update Employment Lifecycle Status -> Denied for HA (90) & Encoder (30)
--              4. Users: Deactivate / Reactivate User Account -> Allowed for HA (90), Denied for Encoder (30)
--              5. Vacancy: Edit Hired Date -> Denied for HA (90) & Encoder (30)
--              6. Approvals: Employee Deactivations Queue -> Denied for HA (90) & Encoder (30)
--              7. Data Control / Approvals: Batch Rollbacks -> Allowed for HA (90), Denied for Encoder (30)
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Synchronize authoritative compatibility table (role_permission_definitions_compat)
INSERT INTO public.role_permission_definitions_compat (module, action_item, role_level, allowed)
VALUES
  -- Vacancy: Edit Hired Date (Ops & SA only; HA 90 & Encoder 30 denied)
  ('Vacancy', 'Edit Hired Date', 90, false),
  ('Vacancy', 'Edit Hired Date', 30, false),

  -- HR Emploc: Approve Deficiency Correction Review (Ops, HR Personnel & SA only; HA 90 & Encoder 30 denied)
  ('HR Emploc', 'Approve Deficiency Correction Review', 90, false),
  ('HR Emploc', 'Approve Deficiency Correction Review', 30, false),

  -- HR Emploc: Revert / Reject Deficiency Correction Review (Ops, HR Personnel & SA only; HA 90 & Encoder 30 denied)
  ('HR Emploc', 'Revert / Reject Deficiency Correction Review', 90, false),
  ('HR Emploc', 'Revert / Reject Deficiency Correction Review', 30, false),

  -- HR Emploc: Rollback / Reject Import Batch (SA & HA only; Encoder 30 denied)
  ('HR Emploc', 'Rollback / Reject Import Batch', 90, true),
  ('HR Emploc', 'Rollback / Reject Import Batch', 30, false),

  -- Plantilla: Update Employment Lifecycle Status (Ops & SA only; HA 90 & Encoder 30 denied)
  ('Plantilla', 'Update Employment Lifecycle Status', 90, false),
  ('Plantilla', 'Update Employment Lifecycle Status', 30, false),

  -- Users: Deactivate / Reactivate User Account (SA & HA only; Encoder 30 denied)
  ('Users', 'Deactivate / Reactivate User Account', 90, true),
  ('Users', 'Deactivate / Reactivate User Account', 30, false)
ON CONFLICT (module, action_item, role_level)
DO UPDATE SET allowed = EXCLUDED.allowed, updated_at = now();

-- 2. Synchronize base matrix table (role_permission_matrix)
INSERT INTO public.role_permission_matrix (role_id, permission_definition_id, is_allowed, source_type)
SELECT r.id, d.id, v.is_allowed, 'rpc_guard'
FROM (
  VALUES
    ('Head Admin', 'vacancy', 'applicant', 'edit_hired_date', false),
    ('Encoder',    'vacancy', 'applicant', 'edit_hired_date', false),
    ('Head Admin', 'hr_emploc', 'deficiency', 'approve_correction', false),
    ('Encoder',    'hr_emploc', 'deficiency', 'approve_correction', false),
    ('Head Admin', 'hr_emploc', 'deficiency', 'reject_correction', false),
    ('Encoder',    'hr_emploc', 'deficiency', 'reject_correction', false),
    ('Head Admin', 'hr_emploc', 'import_batch', 'rollback', true),
    ('Encoder',    'hr_emploc', 'import_batch', 'rollback', false),
    ('Head Admin', 'plantilla', 'lifecycle', 'update_status', false),
    ('Encoder',    'plantilla', 'lifecycle', 'update_status', false),
    ('Head Admin', 'user_management', 'user_status', 'deactivate_reactivate', true),
    ('Encoder',    'user_management', 'user_status', 'deactivate_reactivate', false)
) AS v(role_name, module_key, resource_key, action_key, is_allowed)
JOIN public.roles r ON r.role_name = v.role_name
JOIN public.role_permission_definitions d ON d.module_key = v.module_key AND d.resource_key = v.resource_key AND d.action_key = v.action_key
ON CONFLICT (role_id, permission_definition_id)
DO UPDATE SET is_allowed = EXCLUDED.is_allowed, updated_at = now();
