import test from "node:test";
import assert from "node:assert/strict";

import {
  AppRole,
  normalizeRole,
  getRoleLevel,
  isOwner,
  hasFullAccess,
  isDataTeam,
  isEncoder,
  isOpsTeam,
  canAddApplicant,
  canManageApplicantPipeline,
  canEditApplicantProfile,
  canEditApplicantProfileOnce,
  canReviewVacancyClosures,
  canRequestVacancyClosure,
  canRequestHeadcountAdjustment,
  canReviseHeadcountQuota,
  canViewVacancy,
  canViewCencom,
  canViewHrEmploc,
  canViewPlantilla,
  canViewApprovalsHub,
  canViewReports,
  canManageUsers,
  canViewTeamDirectory,
  getAllowedApprovalCategories,
  isModuleAllowedForUser,
  canPerformDrawerAction,
  DRAWER_ACTION_RULES,
  canEditHiredDate,
  canReopenVacancySlot,
  canRequestApplicantMovement,
  canExportVacancyDataset,
  canApproveDeficiencyCorrection,
  canRevertDeficiencyCorrection,
  canRollbackImportBatch,
  canUpdateEmploymentLifecycleStatus,
  canUpdateWorkSchedule,
  canRequestPoolConversion,
  canRequestRelieverCoverage,
  canSubmitNewStoreRequest,
  canApproveNewStoreRequests,
  canForwardNewStoreRequests,
  canApproveHeadcountAdjustments,
  canApprovePlantillaReassignments,
  canApproveUserSignups,
  canApproveCoverageGroups,
  canApproveApplicantMovements,
  canApproveAccountGroupTransfers,
  canApproveRelieverRequests,
  canGrantElevatedPermissions,
  canDeactivateUserAccount,
  canArchiveUserAccount,
  canAdminForcePasswordReset,
  canTerminateUserSessions,
  canExecuteHrEmplocBulkImport,
  canExecuteVacancyBulkImport,
  canExecutePlantillaBulkImport,
  canExecutePayrollBulkImport,
  canTriggerLiveMikaSync,
  canToggleSystemEditLock,
  canManagePermissionMatrixOverrides,
} from "../../rbac.ts";

const ALL_ROLES = [
  { key: AppRole.SUPER_ADMIN, name: "Super Admin", level: 100 },
  { key: AppRole.HEAD_ADMIN, name: "Head Admin", level: 90 },
  { key: AppRole.OM, name: "Operations Manager", level: 70 },
  { key: AppRole.HRCO, name: "HR Coordinator", level: 45 },
  { key: AppRole.ATL, name: "Assistant Team Leader", level: 42 },
  { key: AppRole.TL, name: "Team Leader", level: 41 },
  { key: AppRole.ENCODER, name: "Encoder", level: 30 },
  { key: AppRole.HR_PERSONNEL, name: "HR Personnel", level: 25 },
  { key: AppRole.RECRUITMENT, name: "Recruitment Specialist", level: 20 },
  { key: AppRole.BACKOFFICE_PERSONNEL, name: "Backoffice Personnel", level: 15 },
  { key: AppRole.VIEWER, name: "Management Viewer", level: 10 },
];

test("Sanity 1: All 11 roles normalize and map to strict numeric levels", () => {
  for (const r of ALL_ROLES) {
    assert.equal(normalizeRole(r.key), r.key, `Failed normalizing key: ${r.key}`);
    assert.equal(normalizeRole(r.name), r.key, `Failed normalizing name: ${r.name}`);
    assert.equal(getRoleLevel(r.key), r.level, `Level mismatch for key: ${r.key}`);
    assert.equal(getRoleLevel(r.name), r.level, `Level mismatch for name: ${r.name}`);
    assert.equal(getRoleLevel({ roleKey: r.key }), r.level);
    assert.equal(getRoleLevel({ roleName: r.name }), r.level);
  }

  // Alias variations
  assert.equal(normalizeRole("Owner"), AppRole.SUPER_ADMIN);
  assert.equal(normalizeRole("SuperAdmin"), AppRole.SUPER_ADMIN);
  assert.equal(normalizeRole("HeadAdmin"), AppRole.HEAD_ADMIN);
  assert.equal(normalizeRole("operations"), AppRole.OM);
  assert.equal(normalizeRole("operationsmanager"), AppRole.OM);
  assert.equal(normalizeRole("Data Team"), AppRole.ENCODER);
  assert.equal(normalizeRole("HR Dept"), AppRole.HR_PERSONNEL);
  assert.equal(normalizeRole("Recruitment Team"), AppRole.RECRUITMENT);
  assert.equal(normalizeRole("Executive Viewer"), AppRole.VIEWER);
  assert.equal(normalizeRole("unknown_role"), null);
  assert.equal(getRoleLevel("unknown_role"), 0);
  assert.equal(getRoleLevel(null), 0);
});

test("Sanity 2: Role grouping predicates maintain strict exclusivity", () => {
  // isOwner
  for (const r of ALL_ROLES) {
    if (r.key === AppRole.SUPER_ADMIN) {
      assert.equal(isOwner(r.key), true, "Super Admin must be owner");
    } else {
      assert.equal(isOwner(r.key), false, `${r.name} must not be owner`);
    }
  }

  // hasFullAccess (SA & HA)
  for (const r of ALL_ROLES) {
    if (r.key === AppRole.SUPER_ADMIN || r.key === AppRole.HEAD_ADMIN) {
      assert.equal(hasFullAccess(r.key), true, `${r.name} must have full access`);
    } else {
      assert.equal(hasFullAccess(r.key), false, `${r.name} must not have full access`);
    }
  }

  // isDataTeam (HA & Encoder)
  for (const r of ALL_ROLES) {
    if (r.key === AppRole.HEAD_ADMIN || r.key === AppRole.ENCODER) {
      assert.equal(isDataTeam(r.key), true, `${r.name} must be Data Team`);
    } else {
      assert.equal(isDataTeam(r.key), false, `${r.name} must not be Data Team`);
    }
  }

  // isEncoder
  for (const r of ALL_ROLES) {
    if (r.key === AppRole.ENCODER) {
      assert.equal(isEncoder(r.key), true, "Encoder must satisfy isEncoder");
    } else {
      assert.equal(isEncoder(r.key), false, `${r.name} must not satisfy isEncoder`);
    }
  }

  // isOpsTeam (OM, HRCO, ATL, TL)
  for (const r of ALL_ROLES) {
    if ([AppRole.OM, AppRole.HRCO, AppRole.ATL, AppRole.TL].includes(r.key)) {
      assert.equal(isOpsTeam(r.key), true, `${r.name} must be Ops Team`);
    } else {
      assert.equal(isOpsTeam(r.key), false, `${r.name} must not be Ops Team`);
    }
  }
});

test("Sanity 3: Module-level allowance (isModuleAllowedForUser) across all 13 modules and getters", () => {
  for (const r of ALL_ROLES) {
    const user = { roleKey: r.key, roleName: r.name, roleLevel: r.level };

    // Common universal modules
    for (const m of ["dashboard", "vacancy", "notifications", "settings", "team_directory", "more"]) {
      assert.equal(isModuleAllowedForUser(m, user), true, `${m} should be allowed for ${r.name}`);
    }
    assert.equal(canViewVacancy(user), true);
    assert.equal(canViewTeamDirectory(user), true);

    // RBAC: STRICTLY Super Admin only
    if (r.key === AppRole.SUPER_ADMIN) {
      assert.equal(isModuleAllowedForUser("rbac", user), true, `rbac must be allowed for Super Admin`);
    } else {
      assert.equal(isModuleAllowedForUser("rbac", user), false, `rbac must be DENIED for ${r.name}`);
    }

    // Users: Super Admin & Head Admin only
    if (r.key === AppRole.SUPER_ADMIN || r.key === AppRole.HEAD_ADMIN) {
      assert.equal(isModuleAllowedForUser("users", user), true, `users must be allowed for ${r.name}`);
      assert.equal(canManageUsers(user), true);
    } else {
      assert.equal(isModuleAllowedForUser("users", user), false, `users must be DENIED for ${r.name}`);
      assert.equal(canManageUsers(user), false);
    }

    // Approvals: SA, HA, Encoder, Backoffice Personnel
    if ([AppRole.SUPER_ADMIN, AppRole.HEAD_ADMIN, AppRole.ENCODER, AppRole.BACKOFFICE_PERSONNEL].includes(r.key)) {
      assert.equal(isModuleAllowedForUser("approvals", user), true, `approvals must be allowed for ${r.name}`);
      assert.equal(canViewApprovalsHub(user), true);
    } else {
      assert.equal(isModuleAllowedForUser("approvals", user), false, `approvals must be DENIED for ${r.name}`);
      assert.equal(canViewApprovalsHub(user), false);
    }

    // CENCOM & Reports: SA, HA, Encoder, OM, ATL, TL, Viewer
    if ([AppRole.SUPER_ADMIN, AppRole.HEAD_ADMIN, AppRole.ENCODER, AppRole.OM, AppRole.ATL, AppRole.TL, AppRole.VIEWER].includes(r.key)) {
      assert.equal(isModuleAllowedForUser("cencom", user), true, `cencom must be allowed for ${r.name}`);
      assert.equal(isModuleAllowedForUser("reports", user), true, `reports must be allowed for ${r.name}`);
      assert.equal(canViewCencom(user), true);
      assert.equal(canViewReports(user), true);
    } else {
      assert.equal(isModuleAllowedForUser("cencom", user), false, `cencom must be DENIED for ${r.name}`);
      assert.equal(isModuleAllowedForUser("reports", user), false, `reports must be DENIED for ${r.name}`);
      assert.equal(canViewCencom(user), false);
      assert.equal(canViewReports(user), false);
    }

    // Plantilla: SA, HA, Ops (OM, HRCO, ATL, TL), Encoder, Viewer
    if ([AppRole.SUPER_ADMIN, AppRole.HEAD_ADMIN, AppRole.OM, AppRole.HRCO, AppRole.ATL, AppRole.TL, AppRole.ENCODER, AppRole.VIEWER].includes(r.key)) {
      assert.equal(isModuleAllowedForUser("plantilla", user), true, `plantilla must be allowed for ${r.name}`);
      assert.equal(canViewPlantilla(user), true);
    } else {
      assert.equal(isModuleAllowedForUser("plantilla", user), false, `plantilla must be DENIED for ${r.name}`);
      assert.equal(canViewPlantilla(user), false);
    }

    // HR Emploc: All roles EXCEPT Recruitment and Viewer
    if ([AppRole.RECRUITMENT, AppRole.VIEWER].includes(r.key)) {
      assert.equal(isModuleAllowedForUser("hr_emploc", user), false, `hr_emploc must be DENIED for ${r.name}`);
      assert.equal(canViewHrEmploc(user), false);
    } else {
      assert.equal(isModuleAllowedForUser("hr_emploc", user), true, `hr_emploc must be allowed for ${r.name}`);
      assert.equal(canViewHrEmploc(user), true);
    }
  }
});

test("Sanity 4: Authoritative Drawer Actions (canPerformDrawerAction) for all 33 actions", () => {
  const allActionKeys = Object.keys(DRAWER_ACTION_RULES);
  assert.equal(allActionKeys.length, 33, "Must have exactly 33 drawer action rules");

  // 1. Super Admin (100) must be allowed on EVERY single action unconditionally
  for (const act of allActionKeys) {
    assert.equal(canPerformDrawerAction(act, "Super Admin"), true, `Super Admin must be allowed on ${act}`);
    assert.equal(canPerformDrawerAction(act, { roleKey: AppRole.SUPER_ADMIN, roleLevel: 100 }), true);
  }

  // 2. Head Admin (90) permissions (explicit drawer action rules)
  const headAdminAllowed = [
    "Export Full Vacancy Dataset",
    "Rollback / Reject Import Batch",
    "Approve / Reject New Store Requests",
    "Approve / Reject Headcount Adjustments",
    "Approve / Reject Plantilla Reassignments",
    "Approve / Reject User Signup Requests",
    "Approve / Reject Coverage Group Requests",
    "Approve / Reject Applicant Movements",
    "Approve / Reject Account Group Transfers",
    "Approve / Reject Reliever Requests",
    "Grant / Revoke Temporary Elevated Permissions",
    "Deactivate / Reactivate User Account",
    "Admin Forced Password Reset",
    "HR Emploc XLSX Bulk Import",
    "Vacancy Roster XLSX Bulk Import",
    "Plantilla Structure XLSX Import",
    "Payroll Hours & Deductions Import",
    "Live MIKA Sync Trigger",
  ];
  for (const act of allActionKeys) {
    const expected = headAdminAllowed.includes(act);
    assert.equal(
      canPerformDrawerAction(act, "Head Admin"),
      expected,
      `Head Admin mismatch on ${act}: expected ${expected}`
    );
  }

  // 3. Encoder (30) permissions
  const encoderAllowed = [
    "Reopen Vacancy Slot",
    "Export Full Vacancy Dataset",
    "Approve / Reject New Store Requests",
    "Approve / Reject Headcount Adjustments",
    "Approve / Reject Plantilla Reassignments",
    "Approve / Reject Applicant Movements",
    "Approve / Reject Reliever Requests",
    "HR Emploc XLSX Bulk Import",
    "Vacancy Roster XLSX Bulk Import",
    "Plantilla Structure XLSX Import",
    "Payroll Hours & Deductions Import",
    "Live MIKA Sync Trigger",
  ];
  for (const act of allActionKeys) {
    const expected = encoderAllowed.includes(act);
    assert.equal(
      canPerformDrawerAction(act, "Encoder"),
      expected,
      `Encoder mismatch on ${act}: expected ${expected}`
    );
  }

  // 4. Operations Team (OM: 70, HRCO: 45, ATL: 42, TL: 41)
  const opsAllowed = [
    "Edit Applicant Profile (Once)",
    "Edit Hired Date",
    "Reopen Vacancy Slot",
    "Request Applicant Movement",
    "Update Employment Lifecycle Status",
    "Update Work Schedule & Day-Off",
    "Request Pool to Regular Slot Conversion",
    "Request Reliever Coverage Assignment",
    "Submit New Store Opening Request",
  ];
  for (const opsRole of ["Operations Manager", "HR Coordinator", "Assistant Team Leader", "Team Leader"]) {
    for (const act of allActionKeys) {
      const expected = opsAllowed.includes(act);
      assert.equal(
        canPerformDrawerAction(act, opsRole),
        expected,
        `${opsRole} mismatch on ${act}: expected ${expected}`
      );
    }
  }

  // 5. HR Personnel (25)
  const hrPersonnelAllowed = [
    "Approve Deficiency Correction Review",
    "Revert / Reject Deficiency Correction Review",
  ];
  for (const act of allActionKeys) {
    const expected = hrPersonnelAllowed.includes(act);
    assert.equal(
      canPerformDrawerAction(act, "HR Personnel"),
      expected,
      `HR Personnel mismatch on ${act}: expected ${expected}`
    );
  }

  // 6. Recruitment Specialist (20)
  const recruitmentAllowed = [
    "Edit Applicant Profile (Once)",
    "Request Applicant Movement",
  ];
  for (const act of allActionKeys) {
    const expected = recruitmentAllowed.includes(act);
    assert.equal(
      canPerformDrawerAction(act, "Recruitment Specialist"),
      expected,
      `Recruitment mismatch on ${act}: expected ${expected}`
    );
  }

  // 7. Management Viewer (10) - ZERO drawer action permissions
  for (const act of allActionKeys) {
    assert.equal(canPerformDrawerAction(act, "Management Viewer"), false, `Viewer must be denied: ${act}`);
  }
});

test("Sanity 5: All 33 individual convenience helpers match canPerformDrawerAction 1:1", () => {
  const helpers = [
    { fn: canEditHiredDate, act: "Edit Hired Date" },
    { fn: canReopenVacancySlot, act: "Reopen Vacancy Slot" },
    { fn: canRequestApplicantMovement, act: "Request Applicant Movement" },
    { fn: canExportVacancyDataset, act: "Export Full Vacancy Dataset" },
    { fn: canApproveDeficiencyCorrection, act: "Approve Deficiency Correction Review" },
    { fn: canRevertDeficiencyCorrection, act: "Revert / Reject Deficiency Correction Review" },
    { fn: canRollbackImportBatch, act: "Rollback / Reject Import Batch" },
    { fn: canUpdateEmploymentLifecycleStatus, act: "Update Employment Lifecycle Status" },
    { fn: canUpdateWorkSchedule, act: "Update Work Schedule & Day-Off" },
    { fn: canRequestPoolConversion, act: "Request Pool to Regular Slot Conversion" },
    { fn: canRequestRelieverCoverage, act: "Request Reliever Coverage Assignment" },
    { fn: canSubmitNewStoreRequest, act: "Submit New Store Opening Request" },
    { fn: canApproveNewStoreRequests, act: "Approve / Reject New Store Requests" },
    { fn: canApproveHeadcountAdjustments, act: "Approve / Reject Headcount Adjustments" },
    { fn: canApprovePlantillaReassignments, act: "Approve / Reject Plantilla Reassignments" },
    { fn: canApproveUserSignups, act: "Approve / Reject User Signup Requests" },
    { fn: canApproveCoverageGroups, act: "Approve / Reject Coverage Group Requests" },
    { fn: canApproveApplicantMovements, act: "Approve / Reject Applicant Movements" },
    { fn: canApproveAccountGroupTransfers, act: "Approve / Reject Account Group Transfers" },
    { fn: canApproveRelieverRequests, act: "Approve / Reject Reliever Requests" },
    { fn: canGrantElevatedPermissions, act: "Grant / Revoke Temporary Elevated Permissions" },
    { fn: canDeactivateUserAccount, act: "Deactivate / Reactivate User Account" },
    { fn: canArchiveUserAccount, act: "Archive / Soft-Delete User Account" },
    { fn: canAdminForcePasswordReset, act: "Admin Forced Password Reset" },
    { fn: canTerminateUserSessions, act: "Terminate Active User Sessions" },
    { fn: canExecuteHrEmplocBulkImport, act: "HR Emploc XLSX Bulk Import" },
    { fn: canExecuteVacancyBulkImport, act: "Vacancy Roster XLSX Bulk Import" },
    { fn: canExecutePlantillaBulkImport, act: "Plantilla Structure XLSX Import" },
    { fn: canExecutePayrollBulkImport, act: "Payroll Hours & Deductions Import" },
    { fn: canTriggerLiveMikaSync, act: "Live MIKA Sync Trigger" },
    { fn: canToggleSystemEditLock, act: "Toggle System Edit Lock (Freeze Mode)" },
    { fn: canManagePermissionMatrixOverrides, act: "Manage Permission Matrix Overrides" },
  ];

  for (const { fn, act } of helpers) {
    for (const r of ALL_ROLES) {
      assert.equal(
        fn(r.key),
        canPerformDrawerAction(act, r.key),
        `Helper ${fn.name} did not match canPerformDrawerAction for ${r.name}`
      );
    }
  }

  // canForwardNewStoreRequests helper (level >= 30)
  for (const r of ALL_ROLES) {
    assert.equal(canForwardNewStoreRequests(r.key), r.level >= 30);
  }
});

test("Sanity 6: Specialized vacancy, applicant, and quota RBAC functions", () => {
  // canAddApplicant & canManageApplicantPipeline (All except Backoffice & Viewer)
  for (const r of ALL_ROLES) {
    if (r.key === AppRole.BACKOFFICE_PERSONNEL || r.key === AppRole.VIEWER) {
      assert.equal(canAddApplicant(r.key), false, `${r.name} should NOT add applicant`);
      assert.equal(canManageApplicantPipeline(r.key), false, `${r.name} should NOT manage pipeline`);
    } else {
      assert.equal(canAddApplicant(r.key), true, `${r.name} should add applicant`);
      assert.equal(canManageApplicantPipeline(r.key), true, `${r.name} should manage pipeline`);
    }
  }

  // canEditApplicantProfile / canEditApplicantProfileOnce (SA, Ops: OM, HRCO, ATL, TL, Recruitment)
  for (const r of ALL_ROLES) {
    const expected = [AppRole.SUPER_ADMIN, AppRole.OM, AppRole.HRCO, AppRole.ATL, AppRole.TL, AppRole.RECRUITMENT].includes(r.key);
    assert.equal(canEditApplicantProfile(r.key), expected, `canEditApplicantProfile mismatch for ${r.name}`);
    assert.equal(canEditApplicantProfileOnce(r.key), expected, `canEditApplicantProfileOnce mismatch for ${r.name}`);
  }

  // canReviewVacancyClosures (SA, HA, Encoder)
  for (const r of ALL_ROLES) {
    const expected = [AppRole.SUPER_ADMIN, AppRole.HEAD_ADMIN, AppRole.ENCODER].includes(r.key);
    assert.equal(canReviewVacancyClosures(r.key), expected, `canReviewVacancyClosures mismatch for ${r.name}`);
  }

  // canRequestVacancyClosure (SA, HA, Ops: OM, HRCO, ATL, TL, Encoder)
  for (const r of ALL_ROLES) {
    const expected = [AppRole.SUPER_ADMIN, AppRole.HEAD_ADMIN, AppRole.OM, AppRole.HRCO, AppRole.ATL, AppRole.TL, AppRole.ENCODER].includes(r.key);
    assert.equal(canRequestVacancyClosure(r.key), expected, `canRequestVacancyClosure mismatch for ${r.name}`);
  }

  // canRequestHeadcountAdjustment (Super Admin only: level >= 100)
  for (const r of ALL_ROLES) {
    assert.equal(canRequestHeadcountAdjustment(r.key), r.level >= 100);
  }

  // canReviseHeadcountQuota (SA, HA, Encoder: Data Team + SA)
  for (const r of ALL_ROLES) {
    const expected = [AppRole.SUPER_ADMIN, AppRole.HEAD_ADMIN, AppRole.ENCODER].includes(r.key);
    assert.equal(canReviseHeadcountQuota(r.key), expected);
  }
});

test("Sanity 7: getAllowedApprovalCategories strictly scopes review queues", () => {
  // Super Admin: 11 categories (all_requests & account_group_transfers removed)
  const saCats = getAllowedApprovalCategories("Super Admin");
  assert.equal(saCats.length, 11);
  assert.ok(!saCats.includes("all_requests"));
  assert.ok(!saCats.includes("account_group_transfers"));
  assert.ok(saCats.includes("account_archives"));

  // Head Admin: 9 categories (no account_archives, no all_requests, no account_group_transfers)
  const haCats = getAllowedApprovalCategories("Head Admin");
  assert.equal(haCats.length, 9);
  assert.ok(!haCats.includes("account_archives"));
  assert.ok(!haCats.includes("all_requests"));
  assert.ok(!haCats.includes("account_group_transfers"));

  // Encoder: 6 operational categories
  const encCats = getAllowedApprovalCategories("Encoder");
  assert.deepEqual(encCats.sort(), [
    "applicant_movements",
    "coverage",
    "headcount",
    "hr_emploc_deletions",
    "relievers",
    "vacancy_closures",
  ].filter(c => encCats.includes(c)).sort());
  assert.equal(encCats.length, 6);

  // Backoffice Personnel: 1 category (deactivations)
  const boCats = getAllowedApprovalCategories("Backoffice Personnel");
  assert.deepEqual(boCats, ["deactivations"]);

  // All other roles: 0 categories
  for (const r of ["Operations Manager", "HR Coordinator", "Assistant Team Leader", "Team Leader", "HR Personnel", "Recruitment Specialist", "Management Viewer"]) {
    assert.deepEqual(getAllowedApprovalCategories(r), [], `${r} must have 0 approval categories`);
  }
});
