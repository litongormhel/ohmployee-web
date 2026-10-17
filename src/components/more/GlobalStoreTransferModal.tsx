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
  X,
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

  if (!isOpen) return null;

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

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-xs animate-in fade-in duration-200">
      <div className="bg-white rounded-2xl shadow-2xl border border-slate-200 w-full max-w-3xl max-h-[90vh] flex flex-col overflow-hidden">
        {/* Header */}
        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between bg-slate-50/50">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-blue-100 text-blue-700 flex items-center justify-center font-bold">
              <Store className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-base font-bold text-slate-900">Global Store Transfer</h2>
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-blue-100 text-blue-800 uppercase tracking-wider">
                  SA Approval Workflow
                </span>
              </div>
              <p className="text-xs text-slate-500">
                Transfer active employees across groups, accounts, and stores with vacant slot assignment
              </p>
            </div>
          </div>

          <button
            type="button"
            onClick={onClose}
            className="p-2 hover:bg-slate-100 rounded-lg text-slate-400 hover:text-slate-600 transition cursor-pointer"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Step Progression Bar */}
        <div className="px-6 py-2.5 bg-slate-100/60 border-b border-slate-200 flex items-center justify-between text-xs font-semibold">
          <div className="flex items-center gap-2">
            <span
              className={`px-2 py-0.5 rounded-md ${
                currentStep === 1
                  ? "bg-blue-600 text-white"
                  : currentStep > 1
                  ? "bg-emerald-100 text-emerald-800"
                  : "bg-slate-200 text-slate-500"
              }`}
            >
              1. Source
            </span>
            <ArrowRight className="w-3 h-3 text-slate-400" />
            <span
              className={`px-2 py-0.5 rounded-md ${
                currentStep === 2
                  ? "bg-blue-600 text-white"
                  : currentStep > 2
                  ? "bg-emerald-100 text-emerald-800"
                  : "bg-slate-200 text-slate-500"
              }`}
            >
              2. Employees ({selectedEmployees.length})
            </span>
            <ArrowRight className="w-3 h-3 text-slate-400" />
            <span
              className={`px-2 py-0.5 rounded-md ${
                currentStep === 3
                  ? "bg-blue-600 text-white"
                  : currentStep > 3
                  ? "bg-emerald-100 text-emerald-800"
                  : "bg-slate-200 text-slate-500"
              }`}
            >
              3. Target & Slot
            </span>
            <ArrowRight className="w-3 h-3 text-slate-400" />
            <span
              className={`px-2 py-0.5 rounded-md ${
                currentStep === 4 ? "bg-blue-600 text-white" : "bg-slate-200 text-slate-500"
              }`}
            >
              4. Review
            </span>
          </div>

          <span className="text-[11px] text-slate-500">Requester: {currentUserFullName}</span>
        </div>

        {/* Error / Alert */}
        {errorMessage && (
          <div className="mx-6 mt-4 p-3 rounded-xl bg-rose-50 border border-rose-200 text-rose-800 text-xs flex items-center gap-2">
            <AlertCircle className="w-4 h-4 shrink-0" />
            <span>{errorMessage}</span>
          </div>
        )}

        {/* Content Body */}
        <div className="p-6 flex-1 overflow-y-auto">
          {submissionSuccess ? (
            <div className="py-12 text-center space-y-4">
              <div className="w-12 h-12 rounded-2xl bg-emerald-100 text-emerald-600 flex items-center justify-center mx-auto">
                <CheckCircle2 className="w-6 h-6" />
              </div>
              <div>
                <h3 className="text-base font-bold text-slate-900">
                  Store Transfer Request Submitted
                </h3>
                <p className="text-xs text-slate-500 max-w-md mx-auto mt-1">
                  Your request has been routed to the Super Admin approval queue (/approvals). On
                  approval, source slots will become vacant and target slots will become occupied.
                </p>
              </div>
              <div className="pt-2">
                <button
                  type="button"
                  onClick={resetAll}
                  className="px-4 py-2 text-xs font-semibold text-blue-600 bg-blue-50 hover:bg-blue-100 rounded-xl transition cursor-pointer"
                >
                  Submit Another Transfer
                </button>
              </div>
            </div>
          ) : currentStep === 1 ? (
            /* Step 1: Source Scope Selection */
            <div className="space-y-4">
              <div className="p-4 rounded-xl border border-slate-200 bg-slate-50/50 space-y-3">
                <div className="flex items-center gap-2 text-xs font-bold text-slate-800">
                  <Layers className="w-4 h-4 text-blue-600" />
                  <span>Select Source Scope</span>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div>
                    <label className="block text-xs font-semibold text-slate-700 mb-1">
                      Source Group *
                    </label>
                    <select
                      value={sourceGroupId}
                      onChange={(e) => {
                        setSourceGroupId(e.target.value);
                        setSourceAccountId("");
                        setSelectedEmployees([]);
                      }}
                      className="w-full p-2.5 text-xs rounded-xl border border-slate-200 bg-white focus:outline-hidden focus:border-blue-500"
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
                    <label className="block text-xs font-semibold text-slate-700 mb-1">
                      Source Account *
                    </label>
                    <select
                      value={sourceAccountId}
                      disabled={!sourceGroupId || isLoadingSourceAccounts}
                      onChange={(e) => {
                        setSourceAccountId(e.target.value);
                        setSelectedEmployees([]);
                      }}
                      className="w-full p-2.5 text-xs rounded-xl border border-slate-200 bg-white focus:outline-hidden focus:border-blue-500 disabled:opacity-50"
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

              <div className="flex justify-end pt-2">
                <button
                  type="button"
                  disabled={!sourceGroupId || !sourceAccountId}
                  onClick={() => setCurrentStep(2)}
                  className="px-5 py-2.5 text-xs font-bold text-white bg-blue-600 hover:bg-blue-700 rounded-xl transition cursor-pointer disabled:opacity-50 flex items-center gap-1.5"
                >
                  <span>Continue to Employee Selection</span>
                  <ChevronRight className="w-4 h-4" />
                </button>
              </div>
            </div>
          ) : currentStep === 2 ? (
            /* Step 2: Employee Selection */
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-xs font-bold text-slate-900">
                    Active Employees in {sourceAccount?.name}
                  </h3>
                  <p className="text-[11px] text-slate-500">
                    Select one or more employees to be transferred
                  </p>
                </div>
                <span className="px-2.5 py-1 rounded-full text-xs font-bold bg-blue-50 text-blue-700 border border-blue-200">
                  {selectedEmployees.length} selected
                </span>
              </div>

              <div className="border border-slate-200 rounded-xl divide-y divide-slate-100 max-h-72 overflow-y-auto bg-white">
                {isLoadingEmployees ? (
                  <div className="p-8 text-center text-xs text-slate-400 flex flex-col items-center gap-2">
                    <RefreshCw className="w-5 h-5 animate-spin text-blue-600" />
                    <span>Loading employees...</span>
                  </div>
                ) : employees.length === 0 ? (
                  <div className="p-8 text-center text-xs text-slate-400">
                    No active employees found for this account.
                  </div>
                ) : (
                  employees.map((emp) => {
                    const isSelected = selectedEmployees.some((e) => e.id === emp.id);
                    return (
                      <div
                        key={emp.id}
                        onClick={() => handleToggleEmployee(emp)}
                        className={`p-3 flex items-center justify-between cursor-pointer transition-colors ${
                          isSelected ? "bg-blue-50/70" : "hover:bg-slate-50"
                        }`}
                      >
                        <div className="flex items-center gap-3">
                          <input
                            type="checkbox"
                            checked={isSelected}
                            onChange={() => {}} // Controlled by outer div
                            className="rounded text-blue-600 focus:ring-blue-500"
                          />
                          <div>
                            <div className="flex items-center gap-2">
                              <span className="text-xs font-bold text-slate-900">
                                {emp.displayName}
                              </span>
                              <span className="text-[10px] text-slate-400">
                                #{emp.employeeNo || "N/A"}
                              </span>
                            </div>
                            <div className="text-[11px] text-slate-500 flex items-center gap-2">
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

              <div className="flex items-center justify-between pt-2">
                <button
                  type="button"
                  onClick={() => setCurrentStep(1)}
                  className="px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-xl transition cursor-pointer"
                >
                  Back
                </button>
                <button
                  type="button"
                  disabled={selectedEmployees.length === 0}
                  onClick={() => setCurrentStep(3)}
                  className="px-5 py-2.5 text-xs font-bold text-white bg-blue-600 hover:bg-blue-700 rounded-xl transition cursor-pointer disabled:opacity-50 flex items-center gap-1.5"
                >
                  <span>Continue to Target Scope</span>
                  <ChevronRight className="w-4 h-4" />
                </button>
              </div>
            </div>
          ) : currentStep === 3 ? (
            /* Step 3: Target Scope & Vacant Slot Assignment */
            <div className="space-y-4">
              <div className="p-4 rounded-xl border border-slate-200 bg-slate-50/50 space-y-3">
                <div className="flex items-center gap-2 text-xs font-bold text-slate-800">
                  <Building className="w-4 h-4 text-blue-600" />
                  <span>Target Destination Scope</span>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  <div>
                    <label className="block text-xs font-semibold text-slate-700 mb-1">
                      Target Group *
                    </label>
                    <select
                      value={targetGroupId}
                      onChange={(e) => {
                        setTargetGroupId(e.target.value);
                        setTargetAccountId("");
                        setTargetStoreId("");
                      }}
                      className="w-full p-2.5 text-xs rounded-xl border border-slate-200 bg-white focus:outline-hidden focus:border-blue-500"
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
                    <label className="block text-xs font-semibold text-slate-700 mb-1">
                      Target Account *
                    </label>
                    <select
                      value={targetAccountId}
                      disabled={!targetGroupId || isLoadingTargetAccounts}
                      onChange={(e) => {
                        setTargetAccountId(e.target.value);
                        setTargetStoreId("");
                      }}
                      className="w-full p-2.5 text-xs rounded-xl border border-slate-200 bg-white focus:outline-hidden focus:border-blue-500 disabled:opacity-50"
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
                    <label className="block text-xs font-semibold text-slate-700 mb-1">
                      Target Store *
                    </label>
                    <select
                      value={targetStoreId}
                      disabled={!targetAccountId || isLoadingTargetStores}
                      onChange={(e) => setTargetStoreId(e.target.value)}
                      className="w-full p-2.5 text-xs rounded-xl border border-slate-200 bg-white focus:outline-hidden focus:border-blue-500 disabled:opacity-50"
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
                  <h4 className="text-xs font-bold text-slate-900">
                    Assign Vacant Slots in {targetStore?.name || "Target Store"}
                  </h4>
                  <span className="text-[11px] text-slate-500">
                    {vacantSlots.length} vacant slots available
                  </span>
                </div>

                <div className="space-y-2">
                  {selectedEmployees.map((emp) => {
                    const assigned = assignedSlotsByEmployeeId[emp.id];
                    return (
                      <div
                        key={emp.id}
                        className="p-3 rounded-xl border border-slate-200 bg-white flex flex-col sm:flex-row sm:items-center justify-between gap-3"
                      >
                        <div>
                          <div className="text-xs font-bold text-slate-900">{emp.displayName}</div>
                          <div className="text-[11px] text-slate-500">
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
                            className="w-full p-2 text-xs rounded-lg border border-slate-200 bg-white focus:outline-hidden focus:border-blue-500 disabled:opacity-50"
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

              <div className="flex items-center justify-between pt-2">
                <button
                  type="button"
                  onClick={() => setCurrentStep(2)}
                  className="px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-xl transition cursor-pointer"
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
                  className="px-5 py-2.5 text-xs font-bold text-white bg-blue-600 hover:bg-blue-700 rounded-xl transition cursor-pointer disabled:opacity-50 flex items-center gap-1.5"
                >
                  <span>Review & Submit</span>
                  <ChevronRight className="w-4 h-4" />
                </button>
              </div>
            </div>
          ) : (
            /* Step 4: Final Review & Submission */
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="p-4 rounded-xl border border-slate-200 bg-slate-50/50 space-y-3">
                <div className="flex items-center justify-between border-b border-slate-200/80 pb-2">
                  <span className="text-xs font-bold text-slate-800">Transfer Plan Summary</span>
                  <span className="text-[10px] font-bold uppercase tracking-wider text-blue-700">
                    {selectedEmployees.length} Transfers
                  </span>
                </div>
                <div className="grid grid-cols-2 gap-4 text-xs">
                  <div>
                    <span className="text-slate-400 block text-[10px] uppercase font-bold">
                      Source Scope
                    </span>
                    <span className="font-semibold text-slate-800">
                      {sourceGroup?.name} ➔ {sourceAccount?.name}
                    </span>
                  </div>
                  <div>
                    <span className="text-slate-400 block text-[10px] uppercase font-bold">
                      Target Scope
                    </span>
                    <span className="font-semibold text-slate-800">
                      {targetGroup?.name} ➔ {targetAccount?.name} ➔ {targetStore?.name}
                    </span>
                  </div>
                </div>
              </div>

              <div className="space-y-2">
                <span className="text-xs font-bold text-slate-800">Employee Slot Transitions</span>
                <div className="border border-slate-200 rounded-xl divide-y divide-slate-100 max-h-48 overflow-y-auto bg-white">
                  {selectedEmployees.map((emp) => {
                    const slot = assignedSlotsByEmployeeId[emp.id];
                    return (
                      <div
                        key={emp.id}
                        className="p-3 text-xs flex items-center justify-between gap-4"
                      >
                        <div>
                          <div className="font-bold text-slate-900">{emp.displayName}</div>
                          <div className="text-[11px] text-slate-500">
                            From: {emp.currentVcode} ({emp.currentStore})
                          </div>
                        </div>
                        <div className="text-right">
                          <div className="font-bold text-blue-700">
                            To: {slot?.vcode || "N/A"}
                          </div>
                          <div className="text-[11px] text-slate-500">
                            {slot?.storeName || targetStore?.name}
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">
                  Reason for Store Transfer *
                </label>
                <textarea
                  required
                  rows={3}
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="e.g. Store expansion, operational balancing, or request by store management"
                  className="w-full p-2.5 text-xs rounded-xl border border-slate-200 bg-white focus:outline-hidden focus:border-blue-500"
                />
              </div>

              <div className="flex items-center justify-between pt-2">
                <button
                  type="button"
                  onClick={() => setCurrentStep(3)}
                  className="px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-xl transition cursor-pointer"
                >
                  Back
                </button>
                <button
                  type="submit"
                  disabled={submitMutation.isPending}
                  className="px-5 py-2.5 text-xs font-bold text-white bg-blue-600 hover:bg-blue-700 rounded-xl transition cursor-pointer disabled:opacity-50 flex items-center gap-1.5"
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

        {/* Footer */}
        <div className="px-6 py-3 border-t border-slate-200 bg-slate-50/70 flex items-center justify-between text-xs text-slate-500">
          <span>Target: StoreTransferApprovalCard (/approvals)</span>
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-semibold text-slate-700 bg-white hover:bg-slate-100 border border-slate-200 rounded-xl transition cursor-pointer"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
