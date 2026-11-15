import React from "react";
import { VacancyDetailDrawer } from "@/components/vacancy/VacancyDetailDrawer";
import { RequestHeadcountModal } from "@/components/modals/RequestHeadcountModal";
import { AssignRelieverModal } from "@/components/plantilla/AssignRelieverModal";
import { ReturnToActiveModal } from "@/components/plantilla/ReturnToActiveModal";
import { AssignStoreModal } from "@/components/plantilla/AssignStoreModal";
import { UpdateEmploymentStatusModal } from "@/components/plantilla/UpdateEmploymentStatusModal";
import { RequestDeactivationModal } from "@/components/plantilla/RequestDeactivationModal";
import { AddAccountModal } from "@/components/plantilla/AddAccountModal";
import { CreateCoverageGroupModal } from "@/components/modals/CreateCoverageGroupModal";
import { ArchiveAccountModal } from "@/components/plantilla/ArchiveAccountModal";
import { AbsorbEmployeesModal } from "@/components/plantilla/AbsorbEmployeesModal";
import { Toast, type ToastVariant } from "@/components/shared/Toast";
import type {
  RelieverTargetEmployee,
  ReturnToActiveTarget,
  AssignStoreTargetEmployee,
  UpdateStatusTargetEmployee,
  DeactivationTargetEmployee,
  ArchiveModalAccount,
  AbsorbModalAccount,
  StoreWithAvailableSlots,
  StatusSubTab,
} from "./types";

export interface PlantillaModalsHubProps {
  // Vacancy Drawer
  selectedVacancyId: string | null;
  onCloseVacancyDrawer: () => void;

  // Request Headcount
  isRequestHeadcountOpen: boolean;
  onCloseRequestHeadcount: () => void;
  accountId: string;
  selectedAccountName: string;
  onRequestHeadcountSuccess: () => void;

  // Assign Reliever
  relieverTargetEmployee: RelieverTargetEmployee | null;
  onCloseAssignReliever: () => void;
  onAssignRelieverSuccess: () => void;

  // Return to Active
  returnToActiveTarget: ReturnToActiveTarget | null;
  onCloseReturnToActive: () => void;
  onReturnToActiveSuccess: () => void;

  // Assign Store
  assignStoreTargetEmployee: AssignStoreTargetEmployee | null;
  onCloseAssignStore: () => void;
  storesWithAvailableSlots: StoreWithAvailableSlots[];
  vacantStoreIds: Set<string>;
  onAssignStoreSuccess: () => void;

  // Update Status
  updateStatusTargetEmployee: UpdateStatusTargetEmployee | null;
  onCloseUpdateStatus: () => void;
  onUpdateStatusSuccess: () => void;
  onNavigateStatusTab: (tab: StatusSubTab) => void;

  // Request Deactivation
  deactivationTargetEmployee: DeactivationTargetEmployee | null;
  onCloseDeactivation: () => void;
  onDeactivationSuccess: () => void;

  // Add Account
  isAddAccountOpen: boolean;
  onCloseAddAccount: () => void;
  onAddAccountSuccess: (createdName: string) => void;

  // Create Coverage Group
  isCreateCoverageGroupOpen: boolean;
  onCloseCreateCoverageGroup: () => void;
  onCreateCoverageGroupSuccess: (code?: string) => void;

  // Archive Account
  archiveModalAccount: ArchiveModalAccount | null;
  onCloseArchiveModal: () => void;
  onRouteArchiveToAbsorption: (acc: AbsorbModalAccount) => void;
  onArchiveSuccess: (name: string) => void;

  // Absorb Employees
  absorbModalAccount: AbsorbModalAccount | null;
  onCloseAbsorbModal: () => void;
  onAbsorbSuccess: (result: { count: number; targetAccountName: string; direct: boolean }) => void;

  // Toast
  toastMessage: string | null;
  toastVariant: ToastVariant;
  onCloseToast: () => void;
}

export function PlantillaModalsHub({
  selectedVacancyId,
  onCloseVacancyDrawer,
  isRequestHeadcountOpen,
  onCloseRequestHeadcount,
  accountId,
  selectedAccountName,
  onRequestHeadcountSuccess,
  relieverTargetEmployee,
  onCloseAssignReliever,
  onAssignRelieverSuccess,
  returnToActiveTarget,
  onCloseReturnToActive,
  onReturnToActiveSuccess,
  assignStoreTargetEmployee,
  onCloseAssignStore,
  storesWithAvailableSlots,
  vacantStoreIds,
  onAssignStoreSuccess,
  updateStatusTargetEmployee,
  onCloseUpdateStatus,
  onUpdateStatusSuccess,
  onNavigateStatusTab,
  deactivationTargetEmployee,
  onCloseDeactivation,
  onDeactivationSuccess,
  isAddAccountOpen,
  onCloseAddAccount,
  onAddAccountSuccess,
  isCreateCoverageGroupOpen,
  onCloseCreateCoverageGroup,
  onCreateCoverageGroupSuccess,
  archiveModalAccount,
  onCloseArchiveModal,
  onRouteArchiveToAbsorption,
  onArchiveSuccess,
  absorbModalAccount,
  onCloseAbsorbModal,
  onAbsorbSuccess,
  toastMessage,
  toastVariant,
  onCloseToast,
}: PlantillaModalsHubProps) {
  return (
    <>
      {/* Vacancy Detail Drawer */}
      <VacancyDetailDrawer
        vacancyId={selectedVacancyId}
        onClose={onCloseVacancyDrawer}
      />

      {/* Request Headcount Modal */}
      {isRequestHeadcountOpen && (
        <RequestHeadcountModal
          isOpen={isRequestHeadcountOpen}
          onClose={onCloseRequestHeadcount}
          accountId={accountId}
          accountName={selectedAccountName}
          onSuccess={onRequestHeadcountSuccess}
        />
      )}

      {/* Assign Reliever Modal (from On-Leave Tab) */}
      {relieverTargetEmployee && (
        <AssignRelieverModal
          isOpen={Boolean(relieverTargetEmployee)}
          onClose={onCloseAssignReliever}
          employee={relieverTargetEmployee}
          accountId={accountId}
          onSuccess={onAssignRelieverSuccess}
        />
      )}

      {/* Return to Active Modal (from On-Leave Tab) */}
      {returnToActiveTarget && (
        <ReturnToActiveModal
          isOpen={Boolean(returnToActiveTarget)}
          onClose={onCloseReturnToActive}
          employee={returnToActiveTarget.employee}
          assignedReliever={returnToActiveTarget.reliever}
          onSuccess={onReturnToActiveSuccess}
        />
      )}

      {/* Assign Store Modal (from Floating Tab) */}
      {assignStoreTargetEmployee && (
        <AssignStoreModal
          isOpen={Boolean(assignStoreTargetEmployee)}
          onClose={onCloseAssignStore}
          employee={assignStoreTargetEmployee}
          stores={storesWithAvailableSlots}
          vacantStoreIds={vacantStoreIds}
          onSuccess={onAssignStoreSuccess}
        />
      )}

      {/* Update Employment Status Modal (from Active Tab) */}
      {updateStatusTargetEmployee && (
        <UpdateEmploymentStatusModal
          isOpen={Boolean(updateStatusTargetEmployee)}
          onClose={onCloseUpdateStatus}
          plantillaId={updateStatusTargetEmployee.id}
          employeeName={updateStatusTargetEmployee.displayName}
          employeeNo={updateStatusTargetEmployee.employeeNo}
          currentStatus={updateStatusTargetEmployee.currentStatus}
          onSuccess={onUpdateStatusSuccess}
          onNavigateStatusTab={(tab) => {
            onNavigateStatusTab(tab as StatusSubTab);
          }}
        />
      )}

      {/* Request Deactivation Modal (from Inactive Tab) */}
      {deactivationTargetEmployee && (
        <RequestDeactivationModal
          isOpen={Boolean(deactivationTargetEmployee)}
          onClose={onCloseDeactivation}
          plantillaId={deactivationTargetEmployee.id}
          employeeName={deactivationTargetEmployee.displayName}
          employeeNo={deactivationTargetEmployee.employeeNo}
          currentStatus={deactivationTargetEmployee.currentStatus}
          onSuccess={onDeactivationSuccess}
          onNavigateStatusTab={(tab) => {
            onNavigateStatusTab(tab as StatusSubTab);
          }}
        />
      )}

      {/* Add Account Modal */}
      {isAddAccountOpen && (
        <AddAccountModal
          isOpen={isAddAccountOpen}
          onClose={onCloseAddAccount}
          onSuccess={onAddAccountSuccess}
        />
      )}

      {/* Create Coverage Group Modal */}
      {isCreateCoverageGroupOpen && (
        <CreateCoverageGroupModal
          isOpen={isCreateCoverageGroupOpen}
          onClose={onCloseCreateCoverageGroup}
          defaultAccountId={accountId || undefined}
          defaultAccountName={selectedAccountName || undefined}
          onSuccess={(created) => onCreateCoverageGroupSuccess(created.coverageCode)}
        />
      )}

      {/* Archive Account Modal */}
      {archiveModalAccount && (
        <ArchiveAccountModal
          isOpen={Boolean(archiveModalAccount)}
          onClose={onCloseArchiveModal}
          account={archiveModalAccount}
          onRouteToAbsorption={onRouteArchiveToAbsorption}
          onSuccess={onArchiveSuccess}
        />
      )}

      {/* Absorb Employees Modal */}
      {absorbModalAccount && (
        <AbsorbEmployeesModal
          isOpen={Boolean(absorbModalAccount)}
          onClose={onCloseAbsorbModal}
          sourceAccount={absorbModalAccount}
          onSuccess={onAbsorbSuccess}
        />
      )}

      {/* Feedback Toast Banner */}
      {toastMessage && (
        <Toast
          isOpen={Boolean(toastMessage)}
          message={toastMessage}
          variant={toastVariant}
          onClose={onCloseToast}
        />
      )}
    </>
  );
}
