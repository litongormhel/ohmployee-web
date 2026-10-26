# UI Modal & Drawer Guard Audit

**Audit Date:** 2026-10-26  
**Total Files Audited:** 101 (88 Modals, 13 Drawers)  
**Shared Wrapper Compliance:** 98 / 101 (85 Shared Modal, 13 Shared DetailDrawer; 3 Justified Overlays: `Modal.tsx` primitive, `IdleWarningModal.tsx` security timeout, `popover.tsx` Radix primitive)

## Complete File Audit Table

| # | File | Type | Wrapper | disableBackdropClick | isSubmitting | dirty-Esc |
| :--- | :--- | :--- | :--- | :---: | :---: | :---: |
| 1 | `src/app/(dashboard)/hr-emploc/page.tsx` | Modal | Shared Modal | No | No | No |
| 2 | `src/components/IdleWarningModal.tsx` | Modal | Custom Overlay (Security Lockout) | No | No | No |
| 3 | `src/components/approvals/AccountRequestDataTable.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 4 | `src/components/approvals/AccountTransferDataTable.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 5 | `src/components/approvals/ApplicantMovementApprovalCard.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 6 | `src/components/approvals/ApplicantMovementDataTable.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 7 | `src/components/approvals/CoverageDataTable.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 8 | `src/components/approvals/CoverageGroupApprovalCard.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 9 | `src/components/approvals/DeactivationApprovalCard.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 10 | `src/components/approvals/DeactivationDataTable.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 11 | `src/components/approvals/HeadcountAmendmentApprovalCard.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 12 | `src/components/approvals/HeadcountDataTable.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 13 | `src/components/approvals/HeadcountStandardApprovalCard.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 14 | `src/components/approvals/HrEmplocDeletionDataTable.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 15 | `src/components/approvals/HrEmplocDeletionReviewCard.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 16 | `src/components/approvals/NewStoreApprovalCard.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 17 | `src/components/approvals/NewStoreDataTable.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 18 | `src/components/approvals/PlantillaApprovalDataTable.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 19 | `src/components/approvals/RelieverCoverageApprovalCard.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 20 | `src/components/approvals/RelieverDataTable.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 21 | `src/components/approvals/StoreTransferApprovalCard.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 22 | `src/components/approvals/VacancyClosureApprovalCard.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 23 | `src/components/approvals/VacancyClosureDataTable.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 24 | `src/components/cencom/CencomQuickReportsTab.tsx` | Modal | Shared Modal | No | No | No |
| 25 | `src/components/dashboard/MikaSyncModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 26 | `src/components/hr-emploc/AssignEmployeeNoModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 27 | `src/components/hr-emploc/DeployToPlantillaModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 28 | `src/components/hr-emploc/HrEmplocDetailDrawer.tsx` | Drawer | Shared Modal | Yes | Yes | Yes |
| 29 | `src/components/hr-emploc/HrEmplocSavedViewsModal.tsx` | Modal | Shared Modal | No | No | No |
| 30 | `src/components/hr-emploc/RequestEmplocDeletionModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 31 | `src/components/hr-emploc/ReviewApproveModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 32 | `src/components/hr-emploc/ReviewRevertModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 33 | `src/components/hr-emploc/SubmitCorrectionModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 34 | `src/components/hr-emploc/TagDeficiencyModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 35 | `src/components/hr-emploc/UploadAttachmentModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 36 | `src/components/hr-emploc/import/BatchDetailsModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 37 | `src/components/hr-emploc/import/RejectBatchModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 38 | `src/components/hr-emploc/import/RollbackBatchModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 39 | `src/components/modals/NewStoreRequestModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 40 | `src/components/modals/RequestHeadcountAdjustmentModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 41 | `src/components/modals/RequestHeadcountModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 42 | `src/components/modals/ReviseHeadcountQuotaModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 43 | `src/components/more/AccessControlCenterModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 44 | `src/components/more/AccountRequestsModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 45 | `src/components/more/AuditLogsModal.tsx` | Modal | Shared Modal | No | No | No |
| 46 | `src/components/more/DataArchivalCenterModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 47 | `src/components/more/EditLockControlModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 48 | `src/components/more/GlobalStoreTransferModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 49 | `src/components/more/HrEmplocImportModal.tsx` | Modal | Shared Modal | No | No | No |
| 50 | `src/components/more/MikaImportModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 51 | `src/components/more/OhmsSafespaceModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 52 | `src/components/more/PayrollImportModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 53 | `src/components/more/PayrollReviewCenterModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 54 | `src/components/more/PermissionDriftModal.tsx` | Modal | Shared Modal | No | No | No |
| 55 | `src/components/more/PermissionMatrixModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 56 | `src/components/more/PlantillaImportModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 57 | `src/components/more/QaCenterModal.tsx` | Modal | Shared Modal | No | No | No |
| 58 | `src/components/more/RolePermissionsModal.tsx` | Modal | Shared Modal | No | No | No |
| 59 | `src/components/more/RovingCoverageGroupsModal.tsx` | Modal | Shared Modal | No | No | No |
| 60 | `src/components/more/SecurityEventsModal.tsx` | Modal | Shared Modal | No | No | No |
| 61 | `src/components/more/SwitchRoleModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 62 | `src/components/more/TempPermissionModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 63 | `src/components/more/VacancyImportModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 64 | `src/components/plantilla/InitiateSeparationModal.tsx` | Modal | Shared Modal | No | Yes | Yes |
| 65 | `src/components/plantilla/PlantillaDetailDrawer.tsx` | Drawer | Shared DetailDrawer | Read-Only / N/A | Read-Only / N/A | Read-Only / N/A |
| 66 | `src/components/plantilla/PoolEmployeeDetailDrawer.tsx` | Drawer | Shared DetailDrawer | Read-Only / N/A | Read-Only / N/A | Read-Only / N/A |
| 67 | `src/components/plantilla/PoolOpenSlotsDrawer.tsx` | Drawer | Shared DetailDrawer | Read-Only / N/A | Read-Only / N/A | Read-Only / N/A |
| 68 | `src/components/plantilla/PoolRequestHistoryDrawer.tsx` | Drawer | Shared DetailDrawer | Read-Only / N/A | Read-Only / N/A | Read-Only / N/A |
| 69 | `src/components/plantilla/PoolReviewQueueDrawer.tsx` | Drawer | Shared DetailDrawer | Read-Only / N/A | Read-Only / N/A | Read-Only / N/A |
| 70 | `src/components/plantilla/RequestDeactivationModal.tsx` | Modal | Shared Modal | No | Yes | Yes |
| 71 | `src/components/plantilla/RequestPoolConversionModal.tsx` | Modal | Shared Modal | No | Yes | Yes |
| 72 | `src/components/plantilla/RequestPoolHeadcountModal.tsx` | Modal | Shared Modal | No | Yes | Yes |
| 73 | `src/components/plantilla/RequestRelieverCoverageModal.tsx` | Modal | Shared Modal | No | Yes | Yes |
| 74 | `src/components/plantilla/SlotDetailDrawer.tsx` | Drawer | Shared DetailDrawer | Read-Only / N/A | Read-Only / N/A | Read-Only / N/A |
| 75 | `src/components/plantilla/StoreStaffingDrawer.tsx` | Drawer | Shared DetailDrawer | Read-Only / N/A | Read-Only / N/A | Read-Only / N/A |
| 76 | `src/components/plantilla/StoreStaffingOverviewDrawer.tsx` | Drawer | Shared DetailDrawer | Read-Only / N/A | Read-Only / N/A | Read-Only / N/A |
| 77 | `src/components/plantilla/TransferPersonnelModal.tsx` | Modal | Shared Modal | No | Yes | Yes |
| 78 | `src/components/plantilla/UpdateEmploymentStatusModal.tsx` | Modal | Shared Modal | No | Yes | Yes |
| 79 | `src/components/plantilla/UpdateScheduleModal.tsx` | Modal | Shared Modal | No | Yes | Yes |
| 80 | `src/components/reports/AttritionDrilldownModal.tsx` | Modal | Shared Modal | No | No | No |
| 81 | `src/components/reports/DataIntegrityDetailModal.tsx` | Modal | Shared Modal | No | No | No |
| 82 | `src/components/reports/TeamPerformanceIssuesModal.tsx` | Modal | Shared Modal | No | No | No |
| 83 | `src/components/settings/ChangePasswordModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 84 | `src/components/settings/SecurityTab.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 85 | `src/components/shared/DetailDrawer.tsx` | Drawer | Shared DetailDrawer | Yes | Yes | Yes |
| 86 | `src/components/shared/Modal.tsx` | Modal | Shared Modal Primitive | Yes | Yes | Yes |
| 87 | `src/components/team-directory/TeamDirectoryDetailDrawer.tsx` | Drawer | Shared DetailDrawer | Read-Only / N/A | Read-Only / N/A | Read-Only / N/A |
| 88 | `src/components/ui/popover.tsx` | Modal | Custom Overlay (Radix Popover) | No | No | No |
| 89 | `src/components/users/CreateUserModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 90 | `src/components/users/TempPermissionModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 91 | `src/components/users/UserDetailDrawer.tsx` | Drawer | Shared Modal | Yes | Yes | Yes |
| 92 | `src/components/vacancy/AddApplicantModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 93 | `src/components/vacancy/AdvancePipelineModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 94 | `src/components/vacancy/EditApplicantModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 95 | `src/components/vacancy/EditHiredDateModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 96 | `src/components/vacancy/FailBackoutModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 97 | `src/components/vacancy/MarkHiredModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 98 | `src/components/vacancy/ReopenVacancyModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 99 | `src/components/vacancy/RequestVacancyClosureModal.tsx` | Modal | Shared Modal | Yes | Yes | Yes |
| 100 | `src/components/vacancy/SavedViewsModal.tsx` | Modal | Shared Modal | No | No | No |
| 101 | `src/components/vacancy/VacancyDetailDrawer.tsx` | Drawer | Shared DetailDrawer | Read-Only / N/A | Read-Only / N/A | Read-Only / N/A |

## Reconciled Summary

- **Total Audited Files:** 101
- **Drawers:** 13 (all 13 wrap `DetailDrawer`)
- **Modals:** 88 (85 use canonical `Modal`, 3 justified overlays)
- **Justified Overlays:**
  1. `src/components/shared/Modal.tsx`: The canonical modal shell primitive itself.
  2. `src/components/IdleWarningModal.tsx`: Explicit security session expiration overlay with countdown; non-dismissable by backdrop or Esc by security policy.
  3. `src/components/ui/popover.tsx`: Radix UI popover primitive for dropdown select positioning.
