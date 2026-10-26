"use client";

import { useState } from "react";
import {
  AlertCircle,
  ArrowRight,
  Building,
  CheckCircle2,
  ChevronRight,
  Layers,
  RefreshCw,
  Send,
  Store,
} from "lucide-react";
import {
  useStoreTransferAccounts,
  useStoreTransferEmployees,
  useStoreTransferGroups,
  useStoreTransferStores,
  useStoreTransferVacantSlots,
  useSubmitGlobalStoreTransfer,
  type StoreTransferEmployeeOption,
} from "@/lib/queries/more";
import { Modal } from "@/components/shared/Modal";

export interface GlobalStoreTransferModalProps {
  isOpen: boolean;
  onClose: () => void;
  currentUserFullName: string;
}

export function GlobalStoreTransferModal({
  isOpen,
  onClose,
  currentUserFullName,
}: GlobalStoreTransferModalProps) {
  // Step State (1: Source Scope, 2: Select Employees, 3: Target Scope & Vacancy, 4: Review)
  const [currentStep, setCurrentStep] = useState<1 | 2 | 3 | 4>(1);

  // Scope & Selection States
  const [sourceGroupId, setSourceGroupId] = useState<string>("");
  const [sourceAccountId, setSourceAccountId] = useState<string>("");

  const [targetGroupId, setTargetGroupId] = useState<string>("");
  const [targetAccountId, setTargetAccountId] = useState<string>("");
  const [targetStoreId, setTargetStoreId] = useState<string>("");

  const [selectedEmployees, setSelectedEmployees] = useState<StoreTransferEmployeeOption[]>([]);
  const [assignedSlotsByEmployeeId, setAssignedSlotsByEmployeeId] = useState<
    Record<string, { id: string; vcode: string; storeName: string; position: string }>
  >({});
  const [reason, setReason] = useState<string>("");
  const [submissionSuccess, setSubmissionSuccess] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Queries
  const { data: groups = [] } = useStoreTransferGroups();

  const sourceGroup = groups.find((g) => g.id === sourceGroupId);
  const targetGroup = groups.find((g) => g.id === targetGroupId);

  const { data: sourceAccounts = [], isLoading: isLoadingSourceAccounts } =
    useStoreTransferAccounts(sourceGroupId || null);
  const { data: targetAccounts = [], isLoading: isLoadingTargetAccounts } =
    useStoreTransferAccounts(targetGroupId || null);

  const sourceAccount = sourceAccounts.find((a) => a.id === sourceAccountId);
  const targetAccount = targetAccounts.find((a) => a.id === targetAccountId);

  const { data: employees = [], isLoading: isLoadingEmployees } = useStoreTransferEmployees({
    groupId: sourceGroupId || null,
    groupName: sourceGroup?.name || "",
    accountId: sourceAccountId || null,
    accountName: sourceAccount?.name || "",
  });

  const { data: targetStores = [], isLoading: isLoadingTargetStores } = useStoreTransferStores({
    groupId: targetGroupId || null,
    accountId: targetAccountId || null,
  });

  const targetStore = targetStores.find((s) => s.id === targetStoreId);

  const { data: vacantSlots = [], isLoading: isLoadingSlots } = useStoreTransferVacantSlots({
    storeId: targetStoreId || null,
    storeName: targetStore?.name || "",
    accountName: targetAccount?.name || "",
    groupName: targetGroup?.name || "",
  });

  const submitMutation = useSubmitGlobalStoreTransfer();

  const handleToggleEmployee = (emp: StoreTransferEmployeeOption) => {
    setSelectedEmployees((prev) => {
      const exists = prev.some((e) => e.id === emp.id);
      if (exists) {
        const next = prev.filter((e) => e.id !== emp.id);
        const nextSlots = { ...assignedSlotsByEmployeeId };
        delete nextSlots[emp.id];
        setAssignedSlotsByEmployeeId(nextSlots);
        return next;
      } else {
        return [...prev, emp];
      }
    });
  };

  const handleAssignSlot = (
    employeeId: string,
    slot: { id: string; vcode: string; storeName: string; position: string }
  ) => {
    setAssignedSlotsByEmployeeId((prev) => ({
      ...prev,
      [employeeId]: slot,
    }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (selectedEmployees.length === 0) {
      setErrorMessage("Please select at least one employee to transfer.");
      return;
    }

    const missingAssignments = selectedEmployees.some((emp) => !assignedSlotsByEmployeeId[emp.id]);
    if (missingAssignments) {
      setErrorMessage("Please assign a vacant slot to every selected employee.");
      return;
    }

    if (!reason.trim()) {
      setErrorMessage("Please provide a reason for the transfer request.");
      return;
    }

    try {
      await submitMutation.mutateAsync({
        sourceScope: `${sourceGroup?.name || ""} / ${sourceAccount?.name || ""}`,
        targetScope: `${targetGroup?.name || ""} / ${targetAccount?.name || ""} / ${
          targetStore?.name || ""
        }`,
        reason: reason.trim(),
        employees: selectedEmployees.map((emp) => {
          const slot = assignedSlotsByEmployeeId[emp.id];
          return {
            employeeId: emp.id,
            employeeName: emp.displayName,
            employeeNo: emp.employeeNo,
            sourceVcode: emp.currentVcode,
            sourceStore: emp.currentStore,
            targetSlotId: slot.id,
            targetVcode: slot.vcode,
            targetStore: slot.storeName,
            position: slot.position || emp.position,
          };
        }),
      });

      setSubmissionSuccess(true);
    } catch (err: unknown) {
      setErrorMessage((err as Error)?.message || "Failed to submit transfer request.");
    }
  };

  const resetAll = () => {
    setCurrentStep(1);
    setSourceGroupId("");
    setSourceAccountId("");
    setTargetGroupId("");
    setTargetAccountId("");
    setTargetStoreId("");
    setSelectedEmployees([]);
    setAssignedSlotsByEmployeeId({});
    setReason("");
    setSubmissionSuccess(false);
    setErrorMessage(null);
  };

  const isFormDirty = selectedEmployees.length > 0 || reason.trim().length > 0;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Global Store Transfer"
      subtitle="Transfer active employees across groups, accounts, and stores with vacant slot assignment"
      icon={Store}
      maxWidthClass="max-w-3xl"
      isSubmitting={submitMutation.isPending}
      disableBackdropClick={submitMutation.isPending}
      isDirty={isFormDirty}
      footer={
        <div className="flex w-full items-center justify-between text-xs text-text-muted">
          <span>Target: StoreTransferApprovalCard (/approvals)</span>
          <button
            type="button"
            onClick={onClose}
            className="rounded-xl border border-border-default bg-surface-primary px-4 py-2 text-xs font-semibold text-text-primary transition hover:bg-surface-hover cursor-pointer"
          >
            Close
          </button>
        </div>
      }
    >
      <div className="space-y-4">
        {/* Step Progression Bar */}
        <div className="p-2.5 bg-surface-subtle border border-border-default rounded-xl flex flex-wrap items-center justify-between text-xs font-semibold gap-2">
          <div className="flex items-center gap-2">
            <span
              className={`px-2.5 py-0.5 rounded-lg text-xs font-bold ${
                currentStep === 1
                  ? "bg-brand-primary text-surface-primary"
                  : currentStep > 1
                  ? "bg-surface-primary text-text-primary border border-border-default"
                  : "bg-surface-subtle text-text-muted"
              }`}
            >
              1. Source
            </span>
            <ArrowRight className="w-3 h-3 text-text-muted" />
            <span
              className={`px-2.5 py-0.5 rounded-lg text-xs font-bold ${
                currentStep === 2
                  ? "bg-brand-primary text-surface-primary"
                  : currentStep > 2
                  ? "bg-surface-primary text-text-primary border border-border-default"
                  : "bg-surface-subtle text-text-muted"
              }`}
            >
              2. Employees ({selectedEmployees.length})
            </span>
            <ArrowRight className="w-3 h-3 text-text-muted" />
            <span
              className={`px-2.5 py-0.5 rounded-lg text-xs font-bold ${
                currentStep === 3
                  ? "bg-brand-primary text-surface-primary"
                  : currentStep > 3
                  ? "bg-surface-primary text-text-primary border border-border-default"
                  : "bg-surface-subtle text-text-muted"
              }`}
            >
              3. Target & Slot
            </span>
            <ArrowRight className="w-3 h-3 text-text-muted" />
            <span
              className={`px-2.5 py-0.5 rounded-lg text-xs font-bold ${
                currentStep === 4 ? "bg-brand-primary text-surface-primary" : "bg-surface-subtle text-text-muted"
              }`}
            >
              4. Review
            </span>
          </div>

          <span className="text-xs text-text-secondary">Requester: {currentUserFullName}</span>
        </div>

        {/* Error / Alert */}
        {errorMessage && (
          <div className="p-3 rounded-xl bg-danger-surface border border-danger-border text-danger-text text-xs flex items-center gap-2">
            <AlertCircle className="w-4 h-4 shrink-0" />
            <span>{errorMessage}</span>
          </div>
        )}

        {/* Content Body */}
        <div className="max-h-[58vh] overflow-y-auto space-y-4 pr-1">
          {submissionSuccess ? (
            <div className="py-12 text-center space-y-4">
              <div className="w-12 h-12 rounded-2xl bg-surface-subtle border border-border-default text-brand-primary flex items-center justify-center mx-auto">
                <CheckCircle2 className="w-6 h-6" />
              </div>
              <div>
                <h3 className="text-sm font-bold text-text-primary">
                  Store Transfer Request Submitted
                </h3>
                <p className="text-xs text-text-secondary max-w-md mx-auto mt-1">
                  Your request has been routed to the Super Admin approval queue (/approvals). On
                  approval, source slots will become vacant and target slots will become occupied.
                </p>
              </div>
              <div className="pt-2">
                <button
                  type="button"
                  onClick={resetAll}
                  className="px-4 py-2 text-xs font-semibold text-brand-primary bg-brand-50 hover:bg-brand-100 rounded-xl transition cursor-pointer"
                >
                  Submit Another Transfer
                </button>
              </div>
            </div>
          ) : currentStep === 1 ? (
            /* Step 1: Source Scope Selection */
            <div className="space-y-4">
              <div className="p-4 rounded-xl border border-border-default bg-surface-subtle space-y-3">
                <div className="flex items-center gap-2 text-xs font-bold text-text-primary">
                  <Layers className="w-4 h-4 text-brand-primary" />
                  <span>Select Source Scope</span>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div>
                    <label className="block text-xs font-bold text-text-primary mb-1">
                      Source Group *
                    </label>
                    <select
                      value={sourceGroupId}
                      onChange={(e) => {
                        setSourceGroupId(e.target.value);
                        setSourceAccountId("");
                        setSelectedEmployees([]);
                      }}
                      className="w-full p-2.5 text-xs rounded-xl border border-border-default bg-surface-primary text-text-primary focus:outline-hidden focus:border-brand-primary"
                    >
                      <option value="">Select Group...</option>
                      {groups.map((g) => (
                        <option key={g.id} value={g.id}>
                          {g.name}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div>
                    <label className="block text-xs font-bold text-text-primary mb-1">
                      Source Account *
                    </label>
                    <select
                      value={sourceAccountId}
                      disabled={!sourceGroupId || isLoadingSourceAccounts}
                      onChange={(e) => {
                        setSourceAccountId(e.target.value);
                        setSelectedEmployees([]);
                      }}
                      className="w-full p-2.5 text-xs rounded-xl border border-border-default bg-surface-primary text-text-primary focus:outline-hidden focus:border-brand-primary disabled:opacity-50"
                    >
                      <option value="">Select Account...</option>
                      {sourceAccounts.map((a) => (
                        <option key={a.id} value={a.id}>
                          {a.name}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>
              </div>

              <div className="flex justify-end pt-2 border-t border-border-default">
                <button
                  type="button"
                  disabled={!sourceGroupId || !sourceAccountId}
                  onClick={() => setCurrentStep(2)}
                  className="px-5 py-2.5 text-xs font-semibold text-surface-primary bg-brand-primary hover:bg-brand-primary-hover rounded-xl transition cursor-pointer disabled:opacity-50 flex items-center gap-1.5"
                >
                  <span>Continue to Employee Selection</span>
                  <ChevronRight className="w-4 h-4" />
                </button>
              </div>
            </div>
          ) : currentStep === 2 ? (
            /* Step 2: Employee Selection */
            <div className="space-y-4">
              <div className="flex items-center justify-between border-b border-border-default pb-3">
                <div>
                  <h3 className="text-sm font-semibold text-text-primary">
                    Active Employees in {sourceAccount?.name}
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Select one or more employees to be transferred
                  </p>
                </div>
                <span className="px-2.5 py-1 rounded-full text-xs font-semibold bg-surface-subtle text-text-primary border border-border-default">
                  {selectedEmployees.length} selected
                </span>
              </div>

              <div className="border border-border-default rounded-2xl divide-y divide-border-subtle max-h-72 overflow-y-auto bg-surface-primary">
                {isLoadingEmployees ? (
                  <div className="p-8 text-center text-xs text-text-muted flex flex-col items-center gap-2">
                    <RefreshCw className="w-5 h-5 animate-spin text-brand-primary" />
                    <span>Loading employees...</span>
                  </div>
                ) : employees.length === 0 ? (
                  <div className="p-8 text-center text-xs text-text-muted">
                    No active employees found for this account.
                  </div>
                ) : (
                  employees.map((emp) => {
                    const isSelected = selectedEmployees.some((e) => e.id === emp.id);
                    return (
                      <div
                        key={emp.id}
                        onClick={() => handleToggleEmployee(emp)}
                        className={`p-3.5 flex items-center justify-between cursor-pointer transition-colors ${
                          isSelected ? "bg-brand-50/50" : "hover:bg-surface-hover"
                        }`}
                      >
                        <div className="flex items-center gap-3">
                          <input
                            type="checkbox"
                            checked={isSelected}
                            onChange={() => {}} // Controlled by outer div
                            className="rounded border-border-default text-brand-primary focus:ring-brand-primary"
                          />
                          <div>
                            <div className="flex items-center gap-2">
                              <span className="text-sm font-semibold text-text-primary">
                                {emp.displayName}
                              </span>
                              <span className="text-xs text-text-muted font-mono">
                                #{emp.employeeNo || "N/A"}
                              </span>
                            </div>
                            <div className="text-xs text-text-secondary flex items-center gap-2 mt-0.5">
                              <span>Store: {emp.currentStore || "Unassigned"}</span>
                              <span>•</span>
                              <span>Vcode: {emp.currentVcode}</span>
                              <span>•</span>
                              <span>{emp.position}</span>
                            </div>
                          </div>
                        </div>
                      </div>
                    );
                  })
                )}
              </div>

              <div className="flex items-center justify-between pt-2 border-t border-border-default">
                <button
                  type="button"
                  onClick={() => setCurrentStep(1)}
                  className="px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover rounded-xl transition cursor-pointer"
                >
                  Back
                </button>
                <button
                  type="button"
                  disabled={selectedEmployees.length === 0}
                  onClick={() => setCurrentStep(3)}
                  className="px-5 py-2.5 text-xs font-semibold text-surface-primary bg-brand-primary hover:bg-brand-primary-hover rounded-xl transition cursor-pointer disabled:opacity-50 flex items-center gap-1.5"
                >
                  <span>Continue to Target Scope</span>
                  <ChevronRight className="w-4 h-4" />
                </button>
              </div>
            </div>
          ) : currentStep === 3 ? (
            /* Step 3: Target Scope & Vacant Slot Assignment */
            <div className="space-y-4">
              <div className="p-4 rounded-xl border border-border-default bg-surface-subtle space-y-3">
                <div className="flex items-center gap-2 text-xs font-bold text-text-primary">
                  <Building className="w-4 h-4 text-brand-primary" />
                  <span>Target Destination Scope</span>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  <div>
                    <label className="block text-xs font-bold text-text-primary mb-1">
                      Target Group *
                    </label>
                    <select
                      value={targetGroupId}
                      onChange={(e) => {
                        setTargetGroupId(e.target.value);
                        setTargetAccountId("");
                        setTargetStoreId("");
                      }}
                      className="w-full p-2.5 text-xs rounded-xl border border-border-default bg-surface-primary text-text-primary focus:outline-hidden focus:border-brand-primary"
                    >
                      <option value="">Select Group...</option>
                      {groups.map((g) => (
                        <option key={g.id} value={g.id}>
                          {g.name}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div>
                    <label className="block text-xs font-bold text-text-primary mb-1">
                      Target Account *
                    </label>
                    <select
                      value={targetAccountId}
                      disabled={!targetGroupId || isLoadingTargetAccounts}
                      onChange={(e) => {
                        setTargetAccountId(e.target.value);
                        setTargetStoreId("");
                      }}
                      className="w-full p-2.5 text-xs rounded-xl border border-border-default bg-surface-primary text-text-primary focus:outline-hidden focus:border-brand-primary disabled:opacity-50"
                    >
                      <option value="">Select Account...</option>
                      {targetAccounts.map((a) => (
                        <option key={a.id} value={a.id}>
                          {a.name}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div>
                    <label className="block text-xs font-bold text-text-primary mb-1">
                      Target Store *
                    </label>
                    <select
                      value={targetStoreId}
                      disabled={!targetAccountId || isLoadingTargetStores}
                      onChange={(e) => setTargetStoreId(e.target.value)}
                      className="w-full p-2.5 text-xs rounded-xl border border-border-default bg-surface-primary text-text-primary focus:outline-hidden focus:border-brand-primary disabled:opacity-50"
                    >
                      <option value="">Select Store...</option>
                      {targetStores.map((s) => (
                        <option key={s.id} value={s.id}>
                          {s.name}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>
              </div>

              {/* Slot Assignments for each selected employee */}
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <h4 className="text-sm font-semibold text-text-primary">
                    Assign Vacant Slots in {targetStore?.name || "Target Store"}
                  </h4>
                  <span className="text-xs text-text-secondary">
                    {vacantSlots.length} vacant slots available
                  </span>
                </div>

                <div className="space-y-2">
                  {selectedEmployees.map((emp) => {
                    const assigned = assignedSlotsByEmployeeId[emp.id];
                    return (
                      <div
                        key={emp.id}
                        className="p-3.5 rounded-xl border border-border-default bg-surface-primary flex flex-col sm:flex-row sm:items-center justify-between gap-3 shadow-2xs"
                      >
                        <div>
                          <div className="text-sm font-semibold text-text-primary">{emp.displayName}</div>
                          <div className="text-xs text-text-secondary">
                            Current: {emp.currentVcode} ({emp.position}) @ {emp.currentStore}
                          </div>
                        </div>

                        <div className="w-full sm:w-64">
                          <select
                            value={assigned?.id || ""}
                            disabled={!targetStoreId || isLoadingSlots}
                            onChange={(e) => {
                              const slot = vacantSlots.find((s) => s.id === e.target.value);
                              if (slot) {
                                handleAssignSlot(emp.id, {
                                  id: slot.id,
                                  vcode: slot.vcode,
                                  storeName: slot.storeName,
                                  position: slot.position,
                                });
                              }
                            }}
                            className="w-full p-2 text-xs rounded-xl border border-border-default bg-surface-primary text-text-primary focus:outline-hidden focus:border-brand-primary disabled:opacity-50"
                          >
                            <option value="">Select Target Slot...</option>
                            {vacantSlots.map((s) => (
                              <option key={s.id} value={s.id}>
                                {s.vcode} - {s.position}
                              </option>
                            ))}
                          </select>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>

              <div className="flex items-center justify-between pt-2 border-t border-border-default">
                <button
                  type="button"
                  onClick={() => setCurrentStep(2)}
                  className="px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover rounded-xl transition cursor-pointer"
                >
                  Back
                </button>
                <button
                  type="button"
                  disabled={
                    !targetStoreId ||
                    selectedEmployees.some((emp) => !assignedSlotsByEmployeeId[emp.id])
                  }
                  onClick={() => setCurrentStep(4)}
                  className="px-5 py-2.5 text-xs font-semibold text-surface-primary bg-brand-primary hover:bg-brand-primary-hover rounded-xl transition cursor-pointer disabled:opacity-50 flex items-center gap-1.5"
                >
                  <span>Review & Submit</span>
                  <ChevronRight className="w-4 h-4" />
                </button>
              </div>
            </div>
          ) : (
            /* Step 4: Final Review & Submission */
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="p-4 rounded-xl border border-border-default bg-surface-subtle space-y-3">
                <div className="flex items-center justify-between border-b border-border-default pb-2">
                  <span className="text-xs font-bold text-text-primary">Transfer Plan Summary</span>
                  <span className="text-xs font-semibold uppercase tracking-wider text-text-secondary">
                    {selectedEmployees.length} Transfers
                  </span>
                </div>
                <div className="grid grid-cols-2 gap-4 text-xs">
                  <div>
                    <span className="text-text-muted block text-xs uppercase font-bold">
                      Source Scope
                    </span>
                    <span className="font-semibold text-text-primary">
                      {sourceGroup?.name} ➔ {sourceAccount?.name}
                    </span>
                  </div>
                  <div>
                    <span className="text-text-muted block text-xs uppercase font-bold">
                      Target Scope
                    </span>
                    <span className="font-semibold text-text-primary">
                      {targetGroup?.name} ➔ {targetAccount?.name} ➔ {targetStore?.name}
                    </span>
                  </div>
                </div>
              </div>

              <div className="space-y-2">
                <span className="text-xs font-bold text-text-primary">Employee Slot Transitions</span>
                <div className="border border-border-default rounded-2xl divide-y divide-border-subtle max-h-48 overflow-y-auto bg-surface-primary">
                  {selectedEmployees.map((emp) => {
                    const slot = assignedSlotsByEmployeeId[emp.id];
                    return (
                      <div
                        key={emp.id}
                        className="p-3.5 text-xs flex items-center justify-between gap-4"
                      >
                        <div>
                          <div className="font-semibold text-sm text-text-primary">{emp.displayName}</div>
                          <div className="text-xs text-text-secondary">
                            From: {emp.currentVcode} ({emp.currentStore})
                          </div>
                        </div>
                        <div className="text-right">
                          <div className="font-semibold text-sm text-text-primary">
                            To: {slot?.vcode || "N/A"}
                          </div>
                          <div className="text-xs text-text-secondary">
                            {slot?.storeName || targetStore?.name}
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-text-primary mb-1">
                  Reason for Store Transfer *
                </label>
                <textarea
                  required
                  rows={3}
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="e.g. Store expansion, operational balancing, or request by store management"
                  className="w-full p-2.5 text-xs rounded-xl border border-border-default bg-surface-primary text-text-primary placeholder:text-text-muted focus:outline-hidden focus:border-brand-primary"
                />
              </div>

              <div className="flex items-center justify-between pt-2 border-t border-border-default">
                <button
                  type="button"
                  onClick={() => setCurrentStep(3)}
                  className="px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover rounded-xl transition cursor-pointer"
                >
                  Back
                </button>
                <button
                  type="submit"
                  disabled={submitMutation.isPending}
                  className="px-5 py-2.5 text-xs font-semibold text-surface-primary bg-brand-primary hover:bg-brand-primary-hover rounded-xl transition cursor-pointer disabled:opacity-50 flex items-center gap-1.5"
                >
                  <Send className="w-3.5 h-3.5" />
                  <span>
                    {submitMutation.isPending ? "Submitting..." : "Submit for SA Approval"}
                  </span>
                </button>
              </div>
            </form>
          )}
        </div>
      </div>
    </Modal>
  );
}
