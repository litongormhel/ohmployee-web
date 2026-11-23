import React from "react";
import { VacancyDetailDrawer } from "@/components/vacancy/VacancyDetailDrawer";
import { RequestHeadcountModal } from "@/components/modals/RequestHeadcountModal";
import {
  NewStoreRequestModal,
  type NewStoreRequestSuccessPayload,
} from "@/components/modals/NewStoreRequestModal";
import { AssignRelieverModal } from "@/components/plantilla/AssignRelieverModal";
import { ReturnToActiveModal } from "@/components/plantilla/ReturnToActiveModal";
import { AssignStoreModal } from "@/components/plantilla/AssignStoreModal";
import { UpdateEmploymentStatusModal } from "@/components/plantilla/UpdateEmploymentStatusModal";
import { RequestDeactivationModal } from "@/components/plantilla/RequestDeactivationModal";
import { AddAccountModal } from "@/components/plantilla/AddAccountModal";
import { CreateCoverageGroupModal } from "@/components/modals/CreateCoverageGroupModal";
import { ArchiveAccountModal } from "@/components/plantilla/ArchiveAccountModal";
import { AbsorbEmployeesModal } from "@/components/plantilla/AbsorbEmployeesModal";
import { TransferAccountGroupModal } from "@/components/plantilla/TransferAccountGroupModal";
import { Toast, type ToastVariant } from "@/components/shared/Toast";
import type { PlantillaScopedAccountItem } from "@/lib/queries/plantilla";
import type {
  RelieverTargetEmployee,
  ReturnToActiveTarget,
  AssignStoreTargetEmployee,
  UpdateStatusTargetEmployee,
  DeactivationTargetEmployee,
  ArchiveModalAccount,
  AbsorbModalAccount,
  StoreWithAvailableSlots,
  StoreCapacityRow,
  StatusSubTab,
} from "./types";

export interface RequestHeadcountConfig {
  mode: "stationary_locked" | "roving_existing";
  store?: StoreCapacityRow;
}

export interface PlantillaModalsHubProps {
  // Vacancy Drawer
  selectedVacancyId: string | null;
  onCloseVacancyDrawer: () => void;

  // Request Headcount
  requestHeadcountConfig: RequestHeadcountConfig | null;
  onCloseRequestHeadcount: () => void;
  accountId: string;
  selectedAccountName: string;
  onRequestHeadcountSuccess: () => void;

  // Request New Store (Independent)
  isNewStoreModalOpen: boolean;
  onCloseNewStoreModal: () => void;
  onNewStoreSuccess: (result: NewStoreRequestSuccessPayload) => void;

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

  // Direct Group Transfer
  transferGroupModalAccount: PlantillaScopedAccountItem | null;
  onCloseTransferGroupModal: () => void;
  onTransferGroupSuccess: (accountName: string, targetGroupName: string) => void;
  uniqueGroups: { id: string; name: string }[];

  // Toast
  toastMessage: string | null;
  toastVariant: ToastVariant;
  onCloseToast: () => void;
}

export function PlantillaModalsHub({
  selectedVacancyId,
  onCloseVacancyDrawer,
  requestHeadcountConfig,
  onCloseRequestHeadcount,
  accountId,
  selectedAccountName,
  onRequestHeadcountSuccess,
  isNewStoreModalOpen,
  onCloseNewStoreModal,
  onNewStoreSuccess,
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
  transferGroupModalAccount,
  onCloseTransferGroupModal,
  onTransferGroupSuccess,
  uniqueGroups,
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
      {requestHeadcountConfig && (
        <RequestHeadcountModal
          isOpen={Boolean(requestHeadcountConfig)}
          onClose={onCloseRequestHeadcount}
          accountId={accountId}
          accountName={selectedAccountName}
          lockedWorkforceType={
            requestHeadcountConfig.mode === "roving_existing" ? "roving" : "stationary"
          }
          lockedStore={requestHeadcountConfig.mode === "stationary_locked"}
          initialStoreId={requestHeadcountConfig.store?.id ?? null}
          initialStoreName={requestHeadcountConfig.store?.storeBranch ?? null}
          initialProvince={requestHeadcountConfig.store?.province ?? null}
          initialCity={requestHeadcountConfig.store?.city ?? null}
          onSuccess={onRequestHeadcountSuccess}
        />
      )}

      {/* Request New Store Modal (Independent) */}
      {isNewStoreModalOpen && (
        <NewStoreRequestModal
          isOpen={isNewStoreModalOpen}
          onClose={onCloseNewStoreModal}
          initialAccountId={accountId}
          initialAccountName={selectedAccountName}
          onSuccess={onNewStoreSuccess}
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

      {/* Transfer Account Group Modal */}
      {transferGroupModalAccount && (
        <TransferAccountGroupModal
          isOpen={Boolean(transferGroupModalAccount)}
          onClose={onCloseTransferGroupModal}
          account={transferGroupModalAccount}
          uniqueGroups={uniqueGroups}
          onSuccess={onTransferGroupSuccess}
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
