-- Migration: 20262606000169_deprecate_dormant_rbac_definitions.sql
-- Description:
--   Permanently deprecates dormant, orphaned, and redundant RBAC permission definitions
--   from role_permission_definitions, role_permission_matrix, and role_permission_overrides:
--     1. hr_emploc.create: HR Emploc records are strictly automated via applicant hire onboarding
--        (confirm_applicant_onboard) or XLSX bulk import (emploc.import); no manual direct creation exists.
--     2. plantilla_slot.add_applicant: Legacy placeholder; applicant slot entry is strictly governed
--        by Vacancy ATS pipeline (applicant.create) and Emploc transfer (plantilla_slot.transfer).
--     3. vacancy.edit: Vacancy properties (position, store, account) are defined by the underlying
--        Plantilla slot and Headcount Request; no manual direct vacancy editing flow exists.

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: NULL OUT AUDIT LOG REFERENCES TO PRESERVE AUDIT TRAIL
-- ═══════════════════════════════════════════════════════════════════════════

UPDATE public.role_permission_audit_logs
SET permission_definition_id = NULL
WHERE permission_definition_id IN (
  SELECT id FROM public.role_permission_definitions
  WHERE (module_key = 'hr_emploc' AND resource_key = 'hr_emploc' AND action_key = 'create')
     OR (module_key = 'plantilla' AND resource_key = 'plantilla_slot' AND action_key = 'add_applicant')
     OR (module_key = 'vacancy' AND resource_key = 'vacancy' AND action_key = 'edit')
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: CLEAN UP FROM role_permission_overrides
-- ═══════════════════════════════════════════════════════════════════════════

DELETE FROM public.role_permission_overrides
WHERE permission_definition_id IN (
  SELECT id FROM public.role_permission_definitions
  WHERE (module_key = 'hr_emploc' AND resource_key = 'hr_emploc' AND action_key = 'create')
     OR (module_key = 'plantilla' AND resource_key = 'plantilla_slot' AND action_key = 'add_applicant')
     OR (module_key = 'vacancy' AND resource_key = 'vacancy' AND action_key = 'edit')
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: CLEAN UP FROM role_permission_matrix
-- ═══════════════════════════════════════════════════════════════════════════

DELETE FROM public.role_permission_matrix
WHERE permission_definition_id IN (
  SELECT id FROM public.role_permission_definitions
  WHERE (module_key = 'hr_emploc' AND resource_key = 'hr_emploc' AND action_key = 'create')
     OR (module_key = 'plantilla' AND resource_key = 'plantilla_slot' AND action_key = 'add_applicant')
     OR (module_key = 'vacancy' AND resource_key = 'vacancy' AND action_key = 'edit')
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: DELETE FROM role_permission_definitions
-- ═══════════════════════════════════════════════════════════════════════════

DELETE FROM public.role_permission_definitions
WHERE (module_key = 'hr_emploc' AND resource_key = 'hr_emploc' AND action_key = 'create')
   OR (module_key = 'plantilla' AND resource_key = 'plantilla_slot' AND action_key = 'add_applicant')
   OR (module_key = 'vacancy' AND resource_key = 'vacancy' AND action_key = 'edit');
