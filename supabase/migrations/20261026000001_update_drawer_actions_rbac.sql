-- ═══════════════════════════════════════════════════════════════════════════
-- Migration: 20261026000001_update_drawer_actions_rbac.sql
-- Description: Synchronize and enforce the 55-item Drawer Actions & Mutations RBAC Matrix
--              across all 11 role levels (Super Admin 100 to Viewer 10).
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Create or ensure compatibility table for drawer actions & mutations matrix
CREATE TABLE IF NOT EXISTS public.role_permission_definitions_compat (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  module      text        NOT NULL,
  action_item text        NOT NULL,
  role_level  integer     NOT NULL,
  allowed     boolean     NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (module, action_item, role_level)
);

CREATE INDEX IF NOT EXISTS idx_rpd_compat_lookup 
  ON public.role_permission_definitions_compat (module, action_item, role_level);

-- 2. Seed / Upsert the authoritative 55-item Drawer Actions & Mutations Matrix
INSERT INTO public.role_permission_definitions_compat (module, action_item, role_level, allowed)
VALUES
-- Vacancy: Edit Applicant Profile (Once)
('Vacancy', 'Edit Applicant Profile (Once)', 100, true),
('Vacancy', 'Edit Applicant Profile (Once)', 90, false),
('Vacancy', 'Edit Applicant Profile (Once)', 70, true),
('Vacancy', 'Edit Applicant Profile (Once)', 45, true),
('Vacancy', 'Edit Applicant Profile (Once)', 42, true),
('Vacancy', 'Edit Applicant Profile (Once)', 41, true),
('Vacancy', 'Edit Applicant Profile (Once)', 30, false),
('Vacancy', 'Edit Applicant Profile (Once)', 25, false),
('Vacancy', 'Edit Applicant Profile (Once)', 20, true),
('Vacancy', 'Edit Applicant Profile (Once)', 15, false),
('Vacancy', 'Edit Applicant Profile (Once)', 10, false),

-- Vacancy: Edit Hired Date
('Vacancy', 'Edit Hired Date', 100, true),
('Vacancy', 'Edit Hired Date', 90, false),
('Vacancy', 'Edit Hired Date', 70, true),
('Vacancy', 'Edit Hired Date', 45, true),
('Vacancy', 'Edit Hired Date', 42, true),
('Vacancy', 'Edit Hired Date', 41, true),
('Vacancy', 'Edit Hired Date', 30, true),
('Vacancy', 'Edit Hired Date', 25, false),
('Vacancy', 'Edit Hired Date', 20, false),
('Vacancy', 'Edit Hired Date', 15, false),
('Vacancy', 'Edit Hired Date', 10, false),

-- Vacancy: Reopen Vacancy Slot
('Vacancy', 'Reopen Vacancy Slot', 100, true),
('Vacancy', 'Reopen Vacancy Slot', 90, false),
('Vacancy', 'Reopen Vacancy Slot', 70, true),
('Vacancy', 'Reopen Vacancy Slot', 45, true),
('Vacancy', 'Reopen Vacancy Slot', 42, true),
('Vacancy', 'Reopen Vacancy Slot', 41, true),
('Vacancy', 'Reopen Vacancy Slot', 30, true),
('Vacancy', 'Reopen Vacancy Slot', 25, false),
('Vacancy', 'Reopen Vacancy Slot', 20, false),
('Vacancy', 'Reopen Vacancy Slot', 15, false),
('Vacancy', 'Reopen Vacancy Slot', 10, false),

-- Vacancy: Request Applicant Movement
('Vacancy', 'Request Applicant Movement', 100, true),
('Vacancy', 'Request Applicant Movement', 90, false),
('Vacancy', 'Request Applicant Movement', 70, true),
('Vacancy', 'Request Applicant Movement', 45, true),
('Vacancy', 'Request Applicant Movement', 42, true),
('Vacancy', 'Request Applicant Movement', 41, true),
('Vacancy', 'Request Applicant Movement', 30, false),
('Vacancy', 'Request Applicant Movement', 25, false),
('Vacancy', 'Request Applicant Movement', 20, true),
('Vacancy', 'Request Applicant Movement', 15, false),
('Vacancy', 'Request Applicant Movement', 10, false),

-- Vacancy: Export Full Vacancy Dataset
('Vacancy', 'Export Full Vacancy Dataset', 100, true),
('Vacancy', 'Export Full Vacancy Dataset', 90, true),
('Vacancy', 'Export Full Vacancy Dataset', 70, false),
('Vacancy', 'Export Full Vacancy Dataset', 45, false),
('Vacancy', 'Export Full Vacancy Dataset', 42, false),
('Vacancy', 'Export Full Vacancy Dataset', 41, false),
('Vacancy', 'Export Full Vacancy Dataset', 30, true),
('Vacancy', 'Export Full Vacancy Dataset', 25, false),
('Vacancy', 'Export Full Vacancy Dataset', 20, false),
('Vacancy', 'Export Full Vacancy Dataset', 15, false),
('Vacancy', 'Export Full Vacancy Dataset', 10, false),

-- HR Emploc: Approve Deficiency Correction Review
('HR Emploc', 'Approve Deficiency Correction Review', 100, true),
('HR Emploc', 'Approve Deficiency Correction Review', 90, false),
('HR Emploc', 'Approve Deficiency Correction Review', 70, true),
('HR Emploc', 'Approve Deficiency Correction Review', 45, true),
('HR Emploc', 'Approve Deficiency Correction Review', 42, true),
('HR Emploc', 'Approve Deficiency Correction Review', 41, true),
('HR Emploc', 'Approve Deficiency Correction Review', 30, true),
('HR Emploc', 'Approve Deficiency Correction Review', 25, true),
('HR Emploc', 'Approve Deficiency Correction Review', 20, false),
('HR Emploc', 'Approve Deficiency Correction Review', 15, false),
('HR Emploc', 'Approve Deficiency Correction Review', 10, false),

-- HR Emploc: Revert / Reject Deficiency Correction Review
('HR Emploc', 'Revert / Reject Deficiency Correction Review', 100, true),
('HR Emploc', 'Revert / Reject Deficiency Correction Review', 90, false),
('HR Emploc', 'Revert / Reject Deficiency Correction Review', 70, true),
('HR Emploc', 'Revert / Reject Deficiency Correction Review', 45, true),
('HR Emploc', 'Revert / Reject Deficiency Correction Review', 42, true),
('HR Emploc', 'Revert / Reject Deficiency Correction Review', 41, true),
('HR Emploc', 'Revert / Reject Deficiency Correction Review', 30, true),
('HR Emploc', 'Revert / Reject Deficiency Correction Review', 25, true),
('HR Emploc', 'Revert / Reject Deficiency Correction Review', 20, false),
('HR Emploc', 'Revert / Reject Deficiency Correction Review', 15, false),
('HR Emploc', 'Revert / Reject Deficiency Correction Review', 10, false),

-- HR Emploc: Rollback / Reject Import Batch
('HR Emploc', 'Rollback / Reject Import Batch', 100, true),
('HR Emploc', 'Rollback / Reject Import Batch', 90, true),
('HR Emploc', 'Rollback / Reject Import Batch', 70, false),
('HR Emploc', 'Rollback / Reject Import Batch', 45, false),
('HR Emploc', 'Rollback / Reject Import Batch', 42, false),
('HR Emploc', 'Rollback / Reject Import Batch', 41, false),
('HR Emploc', 'Rollback / Reject Import Batch', 30, true),
('HR Emploc', 'Rollback / Reject Import Batch', 25, false),
('HR Emploc', 'Rollback / Reject Import Batch', 20, false),
('HR Emploc', 'Rollback / Reject Import Batch', 15, false),
('HR Emploc', 'Rollback / Reject Import Batch', 10, false),

-- Plantilla: Update Employment Lifecycle Status
('Plantilla', 'Update Employment Lifecycle Status', 100, true),
('Plantilla', 'Update Employment Lifecycle Status', 90, false),
('Plantilla', 'Update Employment Lifecycle Status', 70, true),
('Plantilla', 'Update Employment Lifecycle Status', 45, true),
('Plantilla', 'Update Employment Lifecycle Status', 42, true),
('Plantilla', 'Update Employment Lifecycle Status', 41, true),
('Plantilla', 'Update Employment Lifecycle Status', 30, false),
('Plantilla', 'Update Employment Lifecycle Status', 25, false),
('Plantilla', 'Update Employment Lifecycle Status', 20, false),
('Plantilla', 'Update Employment Lifecycle Status', 15, false),
('Plantilla', 'Update Employment Lifecycle Status', 10, false),

-- Plantilla: Update Work Schedule & Day-Off
('Plantilla', 'Update Work Schedule & Day-Off', 100, true),
('Plantilla', 'Update Work Schedule & Day-Off', 90, false),
('Plantilla', 'Update Work Schedule & Day-Off', 70, true),
('Plantilla', 'Update Work Schedule & Day-Off', 45, true),
('Plantilla', 'Update Work Schedule & Day-Off', 42, true),
('Plantilla', 'Update Work Schedule & Day-Off', 41, true),
('Plantilla', 'Update Work Schedule & Day-Off', 30, false),
('Plantilla', 'Update Work Schedule & Day-Off', 25, false),
('Plantilla', 'Update Work Schedule & Day-Off', 20, false),
('Plantilla', 'Update Work Schedule & Day-Off', 15, false),
('Plantilla', 'Update Work Schedule & Day-Off', 10, false),

-- Plantilla: Request Pool to Regular Slot Conversion
('Plantilla', 'Request Pool to Regular Slot Conversion', 100, true),
('Plantilla', 'Request Pool to Regular Slot Conversion', 90, false),
('Plantilla', 'Request Pool to Regular Slot Conversion', 70, true),
('Plantilla', 'Request Pool to Regular Slot Conversion', 45, true),
('Plantilla', 'Request Pool to Regular Slot Conversion', 42, true),
('Plantilla', 'Request Pool to Regular Slot Conversion', 41, true),
('Plantilla', 'Request Pool to Regular Slot Conversion', 30, false),
('Plantilla', 'Request Pool to Regular Slot Conversion', 25, false),
('Plantilla', 'Request Pool to Regular Slot Conversion', 20, false),
('Plantilla', 'Request Pool to Regular Slot Conversion', 15, false),
('Plantilla', 'Request Pool to Regular Slot Conversion', 10, false),

-- Plantilla: Request Reliever Coverage Assignment
('Plantilla', 'Request Reliever Coverage Assignment', 100, true),
('Plantilla', 'Request Reliever Coverage Assignment', 90, false),
('Plantilla', 'Request Reliever Coverage Assignment', 70, true),
('Plantilla', 'Request Reliever Coverage Assignment', 45, true),
('Plantilla', 'Request Reliever Coverage Assignment', 42, true),
('Plantilla', 'Request Reliever Coverage Assignment', 41, true),
('Plantilla', 'Request Reliever Coverage Assignment', 30, false),
('Plantilla', 'Request Reliever Coverage Assignment', 25, false),
('Plantilla', 'Request Reliever Coverage Assignment', 20, false),
('Plantilla', 'Request Reliever Coverage Assignment', 15, false),
('Plantilla', 'Request Reliever Coverage Assignment', 10, false),

-- Plantilla: Submit New Store Opening Request
('Plantilla', 'Submit New Store Opening Request', 100, true),
('Plantilla', 'Submit New Store Opening Request', 90, false),
('Plantilla', 'Submit New Store Opening Request', 70, true),
('Plantilla', 'Submit New Store Opening Request', 45, true),
('Plantilla', 'Submit New Store Opening Request', 42, true),
('Plantilla', 'Submit New Store Opening Request', 41, true),
('Plantilla', 'Submit New Store Opening Request', 30, false),
('Plantilla', 'Submit New Store Opening Request', 25, false),
('Plantilla', 'Submit New Store Opening Request', 20, false),
('Plantilla', 'Submit New Store Opening Request', 15, false),
('Plantilla', 'Submit New Store Opening Request', 10, false),

-- Approvals: Approve / Reject New Store Requests
('Approvals', 'Approve / Reject New Store Requests', 100, true),
('Approvals', 'Approve / Reject New Store Requests', 90, true),
('Approvals', 'Approve / Reject New Store Requests', 70, false),
('Approvals', 'Approve / Reject New Store Requests', 45, false),
('Approvals', 'Approve / Reject New Store Requests', 42, false),
('Approvals', 'Approve / Reject New Store Requests', 41, false),
('Approvals', 'Approve / Reject New Store Requests', 30, false),
('Approvals', 'Approve / Reject New Store Requests', 25, false),
('Approvals', 'Approve / Reject New Store Requests', 20, false),
('Approvals', 'Approve / Reject New Store Requests', 15, false),
('Approvals', 'Approve / Reject New Store Requests', 10, false),

-- Approvals: Approve / Reject Headcount Adjustments
('Approvals', 'Approve / Reject Headcount Adjustments', 100, true),
('Approvals', 'Approve / Reject Headcount Adjustments', 90, true),
('Approvals', 'Approve / Reject Headcount Adjustments', 70, false),
('Approvals', 'Approve / Reject Headcount Adjustments', 45, false),
('Approvals', 'Approve / Reject Headcount Adjustments', 42, false),
('Approvals', 'Approve / Reject Headcount Adjustments', 41, false),
('Approvals', 'Approve / Reject Headcount Adjustments', 30, true),
('Approvals', 'Approve / Reject Headcount Adjustments', 25, false),
('Approvals', 'Approve / Reject Headcount Adjustments', 20, false),
('Approvals', 'Approve / Reject Headcount Adjustments', 15, false),
('Approvals', 'Approve / Reject Headcount Adjustments', 10, false),

-- Approvals: Approve / Reject Plantilla Reassignments
('Approvals', 'Approve / Reject Plantilla Reassignments', 100, true),
('Approvals', 'Approve / Reject Plantilla Reassignments', 90, true),
('Approvals', 'Approve / Reject Plantilla Reassignments', 70, false),
('Approvals', 'Approve / Reject Plantilla Reassignments', 45, false),
('Approvals', 'Approve / Reject Plantilla Reassignments', 42, false),
('Approvals', 'Approve / Reject Plantilla Reassignments', 41, false),
('Approvals', 'Approve / Reject Plantilla Reassignments', 30, true),
('Approvals', 'Approve / Reject Plantilla Reassignments', 25, false),
('Approvals', 'Approve / Reject Plantilla Reassignments', 20, false),
('Approvals', 'Approve / Reject Plantilla Reassignments', 15, false),
('Approvals', 'Approve / Reject Plantilla Reassignments', 10, false),

-- Approvals: Approve / Reject User Signup Requests
('Approvals', 'Approve / Reject User Signup Requests', 100, true),
('Approvals', 'Approve / Reject User Signup Requests', 90, true),
('Approvals', 'Approve / Reject User Signup Requests', 70, false),
('Approvals', 'Approve / Reject User Signup Requests', 45, false),
('Approvals', 'Approve / Reject User Signup Requests', 42, false),
('Approvals', 'Approve / Reject User Signup Requests', 41, false),
('Approvals', 'Approve / Reject User Signup Requests', 30, false),
('Approvals', 'Approve / Reject User Signup Requests', 25, false),
('Approvals', 'Approve / Reject User Signup Requests', 20, false),
('Approvals', 'Approve / Reject User Signup Requests', 15, false),
('Approvals', 'Approve / Reject User Signup Requests', 10, false),

-- Approvals: Approve / Reject Coverage Group Requests
('Approvals', 'Approve / Reject Coverage Group Requests', 100, true),
('Approvals', 'Approve / Reject Coverage Group Requests', 90, true),
('Approvals', 'Approve / Reject Coverage Group Requests', 70, false),
('Approvals', 'Approve / Reject Coverage Group Requests', 45, false),
('Approvals', 'Approve / Reject Coverage Group Requests', 42, false),
('Approvals', 'Approve / Reject Coverage Group Requests', 41, false),
('Approvals', 'Approve / Reject Coverage Group Requests', 30, false),
('Approvals', 'Approve / Reject Coverage Group Requests', 25, false),
('Approvals', 'Approve / Reject Coverage Group Requests', 20, false),
('Approvals', 'Approve / Reject Coverage Group Requests', 15, false),
('Approvals', 'Approve / Reject Coverage Group Requests', 10, false),

-- Approvals: Approve / Reject Applicant Movements
('Approvals', 'Approve / Reject Applicant Movements', 100, true),
('Approvals', 'Approve / Reject Applicant Movements', 90, true),
('Approvals', 'Approve / Reject Applicant Movements', 70, false),
('Approvals', 'Approve / Reject Applicant Movements', 45, false),
('Approvals', 'Approve / Reject Applicant Movements', 42, false),
('Approvals', 'Approve / Reject Applicant Movements', 41, false),
('Approvals', 'Approve / Reject Applicant Movements', 30, true),
('Approvals', 'Approve / Reject Applicant Movements', 25, false),
('Approvals', 'Approve / Reject Applicant Movements', 20, false),
('Approvals', 'Approve / Reject Applicant Movements', 15, false),
('Approvals', 'Approve / Reject Applicant Movements', 10, false),

-- Approvals: Approve / Reject Account Group Transfers
('Approvals', 'Approve / Reject Account Group Transfers', 100, true),
('Approvals', 'Approve / Reject Account Group Transfers', 90, true),
('Approvals', 'Approve / Reject Account Group Transfers', 70, false),
('Approvals', 'Approve / Reject Account Group Transfers', 45, false),
('Approvals', 'Approve / Reject Account Group Transfers', 42, false),
('Approvals', 'Approve / Reject Account Group Transfers', 41, false),
('Approvals', 'Approve / Reject Account Group Transfers', 30, false),
('Approvals', 'Approve / Reject Account Group Transfers', 25, false),
('Approvals', 'Approve / Reject Account Group Transfers', 20, false),
('Approvals', 'Approve / Reject Account Group Transfers', 15, false),
('Approvals', 'Approve / Reject Account Group Transfers', 10, false),

-- Approvals: Approve / Reject Reliever Requests
('Approvals', 'Approve / Reject Reliever Requests', 100, true),
('Approvals', 'Approve / Reject Reliever Requests', 90, true),
('Approvals', 'Approve / Reject Reliever Requests', 70, false),
('Approvals', 'Approve / Reject Reliever Requests', 45, false),
('Approvals', 'Approve / Reject Reliever Requests', 42, false),
('Approvals', 'Approve / Reject Reliever Requests', 41, false),
('Approvals', 'Approve / Reject Reliever Requests', 30, true),
('Approvals', 'Approve / Reject Reliever Requests', 25, false),
('Approvals', 'Approve / Reject Reliever Requests', 20, false),
('Approvals', 'Approve / Reject Reliever Requests', 15, false),
('Approvals', 'Approve / Reject Reliever Requests', 10, false),

-- Users: Grant / Revoke Temporary Elevated Permissions
('Users', 'Grant / Revoke Temporary Elevated Permissions', 100, true),
('Users', 'Grant / Revoke Temporary Elevated Permissions', 90, true),
('Users', 'Grant / Revoke Temporary Elevated Permissions', 70, false),
('Users', 'Grant / Revoke Temporary Elevated Permissions', 45, false),
('Users', 'Grant / Revoke Temporary Elevated Permissions', 42, false),
('Users', 'Grant / Revoke Temporary Elevated Permissions', 41, false),
('Users', 'Grant / Revoke Temporary Elevated Permissions', 30, false),
('Users', 'Grant / Revoke Temporary Elevated Permissions', 25, false),
('Users', 'Grant / Revoke Temporary Elevated Permissions', 20, false),
('Users', 'Grant / Revoke Temporary Elevated Permissions', 15, false),
('Users', 'Grant / Revoke Temporary Elevated Permissions', 10, false),

-- Users: Deactivate / Reactivate User Account
('Users', 'Deactivate / Reactivate User Account', 100, true),
('Users', 'Deactivate / Reactivate User Account', 90, true),
('Users', 'Deactivate / Reactivate User Account', 70, false),
('Users', 'Deactivate / Reactivate User Account', 45, false),
('Users', 'Deactivate / Reactivate User Account', 42, false),
('Users', 'Deactivate / Reactivate User Account', 41, false),
('Users', 'Deactivate / Reactivate User Account', 30, false),
('Users', 'Deactivate / Reactivate User Account', 25, false),
('Users', 'Deactivate / Reactivate User Account', 20, false),
('Users', 'Deactivate / Reactivate User Account', 15, false),
('Users', 'Deactivate / Reactivate User Account', 10, false),

-- Users: Archive / Soft-Delete User Account (SA Only)
('Users', 'Archive / Soft-Delete User Account', 100, true),
('Users', 'Archive / Soft-Delete User Account', 90, false),
('Users', 'Archive / Soft-Delete User Account', 70, false),
('Users', 'Archive / Soft-Delete User Account', 45, false),
('Users', 'Archive / Soft-Delete User Account', 42, false),
('Users', 'Archive / Soft-Delete User Account', 41, false),
('Users', 'Archive / Soft-Delete User Account', 30, false),
('Users', 'Archive / Soft-Delete User Account', 25, false),
('Users', 'Archive / Soft-Delete User Account', 20, false),
('Users', 'Archive / Soft-Delete User Account', 15, false),
('Users', 'Archive / Soft-Delete User Account', 10, false),

-- Users: Admin Forced Password Reset
('Users', 'Admin Forced Password Reset', 100, true),
('Users', 'Admin Forced Password Reset', 90, true),
('Users', 'Admin Forced Password Reset', 70, false),
('Users', 'Admin Forced Password Reset', 45, false),
('Users', 'Admin Forced Password Reset', 42, false),
('Users', 'Admin Forced Password Reset', 41, false),
('Users', 'Admin Forced Password Reset', 30, false),
('Users', 'Admin Forced Password Reset', 25, false),
('Users', 'Admin Forced Password Reset', 20, false),
('Users', 'Admin Forced Password Reset', 15, false),
('Users', 'Admin Forced Password Reset', 10, false),

-- Users: Terminate Active User Sessions (SA Only)
('Users', 'Terminate Active User Sessions', 100, true),
('Users', 'Terminate Active User Sessions', 90, false),
('Users', 'Terminate Active User Sessions', 70, false),
('Users', 'Terminate Active User Sessions', 45, false),
('Users', 'Terminate Active User Sessions', 42, false),
('Users', 'Terminate Active User Sessions', 41, false),
('Users', 'Terminate Active User Sessions', 30, false),
('Users', 'Terminate Active User Sessions', 25, false),
('Users', 'Terminate Active User Sessions', 20, false),
('Users', 'Terminate Active User Sessions', 15, false),
('Users', 'Terminate Active User Sessions', 10, false),

-- Data Control: HR Emploc XLSX Bulk Import
('Data Control', 'HR Emploc XLSX Bulk Import', 100, true),
('Data Control', 'HR Emploc XLSX Bulk Import', 90, true),
('Data Control', 'HR Emploc XLSX Bulk Import', 70, false),
('Data Control', 'HR Emploc XLSX Bulk Import', 45, false),
('Data Control', 'HR Emploc XLSX Bulk Import', 42, false),
('Data Control', 'HR Emploc XLSX Bulk Import', 41, false),
('Data Control', 'HR Emploc XLSX Bulk Import', 30, true),
('Data Control', 'HR Emploc XLSX Bulk Import', 25, false),
('Data Control', 'HR Emploc XLSX Bulk Import', 20, false),
('Data Control', 'HR Emploc XLSX Bulk Import', 15, false),
('Data Control', 'HR Emploc XLSX Bulk Import', 10, false),

-- Data Control: Vacancy Roster XLSX Bulk Import
('Data Control', 'Vacancy Roster XLSX Bulk Import', 100, true),
('Data Control', 'Vacancy Roster XLSX Bulk Import', 90, true),
('Data Control', 'Vacancy Roster XLSX Bulk Import', 70, false),
('Data Control', 'Vacancy Roster XLSX Bulk Import', 45, false),
('Data Control', 'Vacancy Roster XLSX Bulk Import', 42, false),
('Data Control', 'Vacancy Roster XLSX Bulk Import', 41, false),
('Data Control', 'Vacancy Roster XLSX Bulk Import', 30, true),
('Data Control', 'Vacancy Roster XLSX Bulk Import', 25, false),
('Data Control', 'Vacancy Roster XLSX Bulk Import', 20, false),
('Data Control', 'Vacancy Roster XLSX Bulk Import', 15, false),
('Data Control', 'Vacancy Roster XLSX Bulk Import', 10, false),

-- Data Control: Plantilla Structure XLSX Import
('Data Control', 'Plantilla Structure XLSX Import', 100, true),
('Data Control', 'Plantilla Structure XLSX Import', 90, true),
('Data Control', 'Plantilla Structure XLSX Import', 70, false),
('Data Control', 'Plantilla Structure XLSX Import', 45, false),
('Data Control', 'Plantilla Structure XLSX Import', 42, false),
('Data Control', 'Plantilla Structure XLSX Import', 41, false),
('Data Control', 'Plantilla Structure XLSX Import', 30, true),
('Data Control', 'Plantilla Structure XLSX Import', 25, false),
('Data Control', 'Plantilla Structure XLSX Import', 20, false),
('Data Control', 'Plantilla Structure XLSX Import', 15, false),
('Data Control', 'Plantilla Structure XLSX Import', 10, false),

-- Data Control: Payroll Hours & Deductions Import
('Data Control', 'Payroll Hours & Deductions Import', 100, true),
('Data Control', 'Payroll Hours & Deductions Import', 90, true),
('Data Control', 'Payroll Hours & Deductions Import', 70, false),
('Data Control', 'Payroll Hours & Deductions Import', 45, false),
('Data Control', 'Payroll Hours & Deductions Import', 42, false),
('Data Control', 'Payroll Hours & Deductions Import', 41, false),
('Data Control', 'Payroll Hours & Deductions Import', 30, true),
('Data Control', 'Payroll Hours & Deductions Import', 25, false),
('Data Control', 'Payroll Hours & Deductions Import', 20, false),
('Data Control', 'Payroll Hours & Deductions Import', 15, false),
('Data Control', 'Payroll Hours & Deductions Import', 10, false),

-- Data Control: Live MIKA Sync Trigger
('Data Control', 'Live MIKA Sync Trigger', 100, true),
('Data Control', 'Live MIKA Sync Trigger', 90, true),
('Data Control', 'Live MIKA Sync Trigger', 70, false),
('Data Control', 'Live MIKA Sync Trigger', 45, false),
('Data Control', 'Live MIKA Sync Trigger', 42, false),
('Data Control', 'Live MIKA Sync Trigger', 41, false),
('Data Control', 'Live MIKA Sync Trigger', 30, true),
('Data Control', 'Live MIKA Sync Trigger', 25, false),
('Data Control', 'Live MIKA Sync Trigger', 20, false),
('Data Control', 'Live MIKA Sync Trigger', 15, false),
('Data Control', 'Live MIKA Sync Trigger', 10, false),

-- Governance: Toggle System Edit Lock (Freeze Mode) (SA Only)
('Governance', 'Toggle System Edit Lock (Freeze Mode)', 100, true),
('Governance', 'Toggle System Edit Lock (Freeze Mode)', 90, false),
('Governance', 'Toggle System Edit Lock (Freeze Mode)', 70, false),
('Governance', 'Toggle System Edit Lock (Freeze Mode)', 45, false),
('Governance', 'Toggle System Edit Lock (Freeze Mode)', 42, false),
('Governance', 'Toggle System Edit Lock (Freeze Mode)', 41, false),
('Governance', 'Toggle System Edit Lock (Freeze Mode)', 30, false),
('Governance', 'Toggle System Edit Lock (Freeze Mode)', 25, false),
('Governance', 'Toggle System Edit Lock (Freeze Mode)', 20, false),
('Governance', 'Toggle System Edit Lock (Freeze Mode)', 15, false),
('Governance', 'Toggle System Edit Lock (Freeze Mode)', 10, false),

-- Governance: Manage Permission Matrix Overrides (SA Only)
('Governance', 'Manage Permission Matrix Overrides', 100, true),
('Governance', 'Manage Permission Matrix Overrides', 90, false),
('Governance', 'Manage Permission Matrix Overrides', 70, false),
('Governance', 'Manage Permission Matrix Overrides', 45, false),
('Governance', 'Manage Permission Matrix Overrides', 42, false),
('Governance', 'Manage Permission Matrix Overrides', 41, false),
('Governance', 'Manage Permission Matrix Overrides', 30, false),
('Governance', 'Manage Permission Matrix Overrides', 25, false),
('Governance', 'Manage Permission Matrix Overrides', 20, false),
('Governance', 'Manage Permission Matrix Overrides', 15, false),
('Governance', 'Manage Permission Matrix Overrides', 10, false)

ON CONFLICT (module, action_item, role_level) 
DO UPDATE SET 
  allowed = EXCLUDED.allowed,
  updated_at = now();

-- 3. Register Definition Catalog in public.role_permission_definitions
INSERT INTO public.role_permission_definitions
  (module_key, resource_key, action_key, scope_mode, enforcement_type, description, is_sensitive, is_system_locked, sort_order)
VALUES
  -- Vacancy Drawer Actions
  ('vacancy', 'applicant', 'edit_profile_once', 'account', 'rpc', 'Edit Applicant Profile (Once)', true, false, 120),
  ('vacancy', 'applicant', 'edit_hired_date',   'account', 'rpc', 'Edit Hired Date', true, false, 130),
  ('vacancy', 'vacancy',   'reopen_slot',       'account', 'rpc', 'Reopen Vacancy Slot', true, false, 140),
  ('vacancy', 'applicant', 'request_movement',  'account', 'rpc', 'Request Applicant Movement', false, false, 150),
  ('vacancy', 'vacancy',   'export_dataset',    'global',  'rpc', 'Export Full Vacancy Dataset', true, false, 160),

  -- HR Emploc Mutations
  ('hr_emploc', 'deficiency',   'approve_correction', 'account', 'rpc', 'Approve Deficiency Correction Review', true, false, 40),
  ('hr_emploc', 'deficiency',   'reject_correction',  'account', 'rpc', 'Revert / Reject Deficiency Correction Review', true, false, 50),
  ('hr_emploc', 'import_batch', 'rollback',           'global',  'rpc', 'Rollback / Reject Import Batch', true, false, 60),

  -- Plantilla Mutations
  ('plantilla', 'lifecycle', 'update_status',     'account', 'rpc', 'Update Employment Lifecycle Status', true, false, 50),
  ('plantilla', 'schedule',  'update_schedule',   'account', 'rpc', 'Update Work Schedule & Day-Off', false, false, 60),
  ('plantilla', 'pool_slot', 'request_conversion','account', 'rpc', 'Request Pool to Regular Slot Conversion', false, false, 70),
  ('plantilla', 'reliever',  'request_coverage',  'account', 'rpc', 'Request Reliever Coverage Assignment', false, false, 80),
  ('plantilla', 'new_store', 'submit_request',    'account', 'rpc', 'Submit New Store Opening Request', true, false, 90),

  -- User Management Mutations
  ('user_management', 'elevated_permissions', 'manage',               'global', 'rpc', 'Grant / Revoke Temporary Elevated Permissions', true, true, 50),
  ('user_management', 'user_status',          'deactivate_reactivate','global', 'rpc', 'Deactivate / Reactivate User Account', true, true, 60),
  ('user_management', 'user_account',         'archive',              'global', 'rpc', 'Archive / Soft-Delete User Account (SA Only)', true, true, 70),
  ('user_management', 'user_password',        'force_reset',          'global', 'rpc', 'Admin Forced Password Reset', true, true, 80),

  -- Data Control Actions
  ('data_control', 'hr_emploc_import', 'execute', 'global', 'rpc', 'HR Emploc XLSX Bulk Import', true, false, 10),
  ('data_control', 'vacancy_import',   'execute', 'global', 'rpc', 'Vacancy Roster XLSX Bulk Import', true, false, 20),
  ('data_control', 'plantilla_import', 'execute', 'global', 'rpc', 'Plantilla Structure XLSX Import', true, false, 30),
  ('data_control', 'payroll_import',   'execute', 'global', 'rpc', 'Payroll Hours & Deductions Import', true, false, 40),
  ('data_control', 'mika_sync',        'trigger', 'global', 'rpc', 'Live MIKA Sync Trigger', true, false, 50),

  -- Governance Actions
  ('governance', 'edit_lock',            'toggle', 'global', 'rpc', 'Toggle System Edit Lock (Freeze Mode)', true, true, 10),
  ('governance', 'permission_overrides', 'manage', 'global', 'rpc', 'Manage Permission Matrix Overrides', true, true, 20)
ON CONFLICT (module_key, resource_key, action_key, scope_mode) DO NOTHING;

-- 4. Cross-join deny-fill for matrix integrity
INSERT INTO public.role_permission_matrix (role_id, permission_definition_id, is_allowed, source_type)
SELECT r.id, d.id, false, 'rpc_guard'
FROM public.roles r
CROSS JOIN public.role_permission_definitions d
WHERE r.role_name IN (
  'Super Admin', 'Head Admin', 'Operations Manager', 'OM', 'HRCO',
  'ATL', 'TL', 'ATL/TL', 'Encoder', 'HR Personnel',
  'Recruitment Team', 'Recruitment',
  'Back Office', 'Backoffice', 'Backoffice Personnel', 'Viewer'
)
ON CONFLICT (role_id, permission_definition_id) DO NOTHING;
