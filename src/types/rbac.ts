/**
 * RBAC Matrix Types & Constants
 * 
 * Synchronized with:
 * - OHMployee Web vs Mobile RBAC Matrix (All Roles) - Drawer Actions & Mutations
 * - PostgreSQL role_permission_definitions / role_permission_matrix
 */

export type RoleLevel = 100 | 90 | 70 | 45 | 42 | 41 | 30 | 25 | 20 | 15 | 10;

export type DrawerActionModule =
  | "Vacancy"
  | "HR Emploc"
  | "Plantilla"
  | "Approvals"
  | "Users"
  | "Data Control"
  | "Governance";

export type DrawerActionItem =
  // Vacancy
  | "Edit Applicant Profile (Once)"
  | "Edit Hired Date"
  | "Reopen Vacancy Slot"
  | "Request Applicant Movement"
  | "Export Full Vacancy Dataset"
  // HR Emploc
  | "Approve Deficiency Correction Review"
  | "Revert / Reject Deficiency Correction Review"
  | "Rollback / Reject Import Batch"
  // Plantilla
  | "Update Employment Lifecycle Status"
  | "Update Work Schedule & Day-Off"
  | "Request Pool to Regular Slot Conversion"
  | "Request Reliever Coverage Assignment"
  | "Submit New Store Opening Request"
  // Approvals
  | "Approve / Reject New Store Requests"
  | "Approve / Reject Headcount Adjustments"
  | "Approve / Reject Plantilla Reassignments"
  | "Approve / Reject User Signup Requests"
  | "Approve / Reject Coverage Group Requests"
  | "Approve / Reject Applicant Movements"
  | "Approve / Reject Account Group Transfers"
  | "Approve / Reject Reliever Requests"
  // Users
  | "Grant / Revoke Temporary Elevated Permissions"
  | "Deactivate / Reactivate User Account"
  | "Archive / Soft-Delete User Account"
  | "Admin Forced Password Reset"
  | "Terminate Active User Sessions"
  // Data Control
  | "HR Emploc XLSX Bulk Import"
  | "Vacancy Roster XLSX Bulk Import"
  | "Plantilla Structure XLSX Import"
  | "Payroll Hours & Deductions Import"
  | "Live MIKA Sync Trigger"
  // Governance
  | "Toggle System Edit Lock (Freeze Mode)"
  | "Manage Permission Matrix Overrides";

export interface RolePermissionRule {
  module: DrawerActionModule;
  actionItem: DrawerActionItem;
  allowedRoleLevels: number[];
}
