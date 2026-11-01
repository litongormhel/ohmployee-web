"use client";

import { useState, useMemo } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowRightLeft,
  Search,
  CheckSquare,
  Square,
  Loader2,
  AlertCircle,
  ShieldCheck,
  Clock,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { useCurrentUser, isHeadOrSuperAdmin } from "@/lib/auth";
import {
  listWebPlantillaEmployees,
  fetchPlantillaScopedAccounts,
  absorbEmployees,
} from "@/lib/queries/plantilla";

export interface AbsorbEmployeesModalProps {
  isOpen: boolean;
  onClose: () => void;
  sourceAccount: {
    id: string;
    name: string;
  } | null;
  onSuccess?: (result: { direct: boolean; count: number; targetAccountName: string }) => void;
}

export function AbsorbEmployeesModal({
  isOpen,
  onClose,
  sourceAccount,
  onSuccess,
}: AbsorbEmployeesModalProps) {
  const [targetAccountId, setTargetAccountId] = useState("");
  const [selectedEmployeeIds, setSelectedEmployeeIds] = useState<string[]>([]);
  const [searchQuery, setSearchQuery] = useState("");
  const [notes, setNotes] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const currentUser = useCurrentUser();
  const queryClient = useQueryClient();

  const userRole = currentUser?.roleKey ?? currentUser?.roleName;
  const isDirect = isHeadOrSuperAdmin(userRole);

  // Fetch destination accounts available to the current user
  const accountsQuery = useQuery({
    queryKey: ["plantilla", "allowed-accounts", currentUser?.accountScope, currentUser?.groupScope],
    queryFn: () => fetchPlantillaScopedAccounts(currentUser),
    enabled: isOpen && !!currentUser,
    staleTime: 60_000,
  });

  // Filter out the source account
  const destinationAccounts = useMemo(() => {
    const list = accountsQuery.data ?? [];
    if (!sourceAccount) return list;
    return list.filter((a) => a.id !== sourceAccount.id);
  }, [accountsQuery.data, sourceAccount]);

  // Fetch active employees for source account
  const employeesQuery = useQuery({
    queryKey: ["plantilla", "absorb-source-employees", sourceAccount?.id],
    queryFn: () =>
      listWebPlantillaEmployees({
        accountId: sourceAccount!.id,
        activeState: "active",
        page: 1,
        pageSize: 500,
      }),
    enabled: isOpen && !!sourceAccount?.id,
    staleTime: 30_000,
  });

  const activeEmployees = useMemo(() => {
    return employeesQuery.data?.data ?? [];
  }, [employeesQuery.data]);

  // Filter employees by local search query
  const filteredEmployees = useMemo(() => {
    if (!searchQuery.trim()) return activeEmployees;
    const q = searchQuery.toLowerCase().trim();
    return activeEmployees.filter((emp) => {
      const name = emp.fullName || `${emp.firstName ?? ""} ${emp.lastName ?? ""}`.trim();
      return (
        name.toLowerCase().includes(q) ||
        emp.employeeNo.toLowerCase().includes(q) ||
        (emp.positionTitle && emp.positionTitle.toLowerCase().includes(q)) ||
        (emp.primaryStoreName && emp.primaryStoreName.toLowerCase().includes(q))
      );
    });
  }, [activeEmployees, searchQuery]);

  // Selection helpers
  const isAllFilteredSelected =
    filteredEmployees.length > 0 &&
    filteredEmployees.every((emp) => selectedEmployeeIds.includes(emp.id));

  const toggleSelectAll = () => {
    if (isAllFilteredSelected) {
      const filteredIds = new Set(filteredEmployees.map((e) => e.id));
      setSelectedEmployeeIds((prev) => prev.filter((id) => !filteredIds.has(id)));
    } else {
      const current = new Set(selectedEmployeeIds);
      filteredEmployees.forEach((e) => current.add(e.id));
      setSelectedEmployeeIds(Array.from(current));
    }
  };

  const toggleSelectOne = (id: string) => {
    setSelectedEmployeeIds((prev) =>
      prev.includes(id) ? prev.filter((item) => item !== id) : [...prev, id],
    );
  };

  const handleClose = () => {
    if (isSubmitting) return;
    setTargetAccountId("");
    setSelectedEmployeeIds([]);
    setSearchQuery("");
    setNotes("");
    setErrorMessage(null);
    onClose();
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!sourceAccount) return;
    if (!targetAccountId) {
      setErrorMessage("Please select a target destination account.");
      return;
    }
    if (selectedEmployeeIds.length === 0) {
      setErrorMessage("Please select at least one employee to absorb.");
      return;
    }

    const targetAccount = destinationAccounts.find((a) => a.id === targetAccountId);
    if (!targetAccount) {
      setErrorMessage("Selected target account not found.");
      return;
    }

    const selectedEmployeesData = activeEmployees
      .filter((emp) => selectedEmployeeIds.includes(emp.id))
      .map((emp) => ({
        id: emp.id,
        employeeNo: emp.employeeNo,
        name: emp.fullName || `${emp.firstName ?? ""} ${emp.lastName ?? ""}`.trim() || emp.employeeNo,
        vcode: emp.vcode,
        primaryStoreName: emp.primaryStoreName,
      }));

    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      const result = await absorbEmployees({
        sourceAccountId: sourceAccount.id,
        sourceAccountName: sourceAccount.name,
        targetAccountId: targetAccount.id,
        targetAccountName: targetAccount.name,
        employees: selectedEmployeesData,
        isDirectExecution: isDirect,
        requestedBy: currentUser?.profileId ?? currentUser?.authUserId,
        requestedByRole: userRole ?? (isDirect ? "Head Admin" : "Encoder"),
        notes: notes.trim() || null,
      });

      // Invalidate relevant queries so UI reflects absorption
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["team-directory"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla", "employees-all"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla", "allowed-accounts"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla", "account-metrics"] });
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });

      handleClose();
      onSuccess?.({
        direct: result.direct,
        count: result.count,
        targetAccountName: targetAccount.name,
      });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Failed to execute absorption.";
      setErrorMessage(msg);
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!sourceAccount) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Absorb Employees"
      subtitle={`Source Account: ${sourceAccount.name}`}
      icon={ArrowRightLeft}
      maxWidthClass="max-w-2xl"
      isDirty={selectedEmployeeIds.length > 0 || targetAccountId !== ""}
      isSubmitting={isSubmitting}
      footer={
        <div className="flex items-center justify-between w-full">
          <div className="text-xs text-text-secondary">
            <span className="font-semibold text-text-primary">{selectedEmployeeIds.length}</span>{" "}
            employee{selectedEmployeeIds.length === 1 ? "" : "s"} selected
          </div>
          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={handleClose}
              disabled={isSubmitting}
              className="rounded-lg border border-border-default bg-surface-base px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition cursor-pointer disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleSubmit}
              disabled={isSubmitting || !targetAccountId || selectedEmployeeIds.length === 0}
              className="inline-flex items-center justify-center gap-1.5 rounded-lg bg-brand-button px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-brand-button-hover transition cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isSubmitting && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
              <span>
                {isSubmitting
                  ? "Processing..."
                  : isDirect
                  ? `Absorb ${selectedEmployeeIds.length} Directly`
                  : `Submit ${selectedEmployeeIds.length} for Approval`}
              </span>
            </button>
          </div>
        </div>
      }
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {errorMessage && (
          <div className="flex items-start gap-2.5 rounded-lg border border-danger-border bg-danger-bg p-3 text-xs text-danger-text">
            <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
            <p className="leading-relaxed">{errorMessage}</p>
          </div>
        )}

        {/* Role Governance Banner */}
        <div
          className={`flex items-start gap-2.5 rounded-lg border p-3 text-xs ${
            isDirect
              ? "border-brand-200/80 bg-brand-50/50 dark:bg-brand-950/20 text-brand-900 dark:text-brand-200"
              : "border-pct-warn-border bg-pct-warn-bg/20 text-text-primary"
          }`}
        >
          {isDirect ? (
            <ShieldCheck className="h-4 w-4 shrink-0 text-brand-600 mt-0.5" />
          ) : (
            <Clock className="h-4 w-4 shrink-0 text-pct-warn-text mt-0.5" />
          )}
          <div className="space-y-0.5 leading-relaxed">
            <p className="font-semibold">
              {isDirect
                ? "Direct Database Execution (HA / SA)"
                : "Approval Routing Required (Encoder)"}
            </p>
            <p className="text-text-secondary">
              {isDirect
                ? "As Head Admin or Super Admin, submitting this form immediately updates the assigned accounts in Supabase and refreshes the roster."
                : "As an Encoder, submitting will create a pending record in the Approvals queue. The employees' accounts will update once approved by an SA or HA."}
            </p>
          </div>
        </div>

        {/* Target Destination Account Selection */}
        <div>
          <label className="block text-xs font-semibold text-text-primary mb-1">
            Target Destination Account <span className="text-danger-text">*</span>
          </label>
          {accountsQuery.isLoading ? (
            <div className="flex items-center gap-2 py-2 text-xs text-text-secondary">
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
              <span>Loading destination accounts...</span>
            </div>
          ) : (
            <select
              value={targetAccountId}
              onChange={(e) => setTargetAccountId(e.target.value)}
              disabled={isSubmitting}
              className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none transition-colors"
            >
              <option value="">Select target destination account...</option>
              {destinationAccounts.map((account) => (
                <option key={account.id} value={account.id}>
                  {account.groupName ? `${account.groupName} • ` : ""}
                  {account.name}
                </option>
              ))}
            </select>
          )}
        </div>

        {/* Active Employee Roster Selection */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <label className="text-xs font-semibold text-text-primary">
              Select Employees to Transfer <span className="text-danger-text">*</span>
            </label>
            <span className="text-xs text-text-secondary">
              Total Active: {activeEmployees.length}
            </span>
          </div>

          {/* Search Box */}
          <div className="relative">
            <Search className="absolute left-3 top-2.5 h-4 w-4 text-text-muted" />
            <input
              type="text"
              placeholder="Search by name, employee #, position, or store..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              disabled={isSubmitting}
              className="w-full rounded-lg border border-border-default bg-surface-base pl-9 pr-3 py-1.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none transition-colors"
            />
          </div>

          {/* Table Container */}
          <div className="max-h-60 overflow-y-auto rounded-lg border border-border-default bg-surface-base">
            {employeesQuery.isLoading ? (
              <div className="flex flex-col items-center justify-center p-8 gap-2 text-xs text-text-secondary">
                <Loader2 className="h-5 w-5 animate-spin text-brand-600" />
                <span>Fetching active personnel roster...</span>
              </div>
            ) : filteredEmployees.length === 0 ? (
              <div className="p-6 text-center text-xs text-text-muted">
                {activeEmployees.length === 0
                  ? "No active employees found in this account."
                  : "No employees match your search query."}
              </div>
            ) : (
              <table className="w-full text-left text-xs border-collapse">
                <thead className="sticky top-0 bg-surface-muted border-b border-border-subtle z-10">
                  <tr>
                    <th className="p-2.5 w-10">
                      <button
                        type="button"
                        onClick={toggleSelectAll}
                        disabled={isSubmitting}
                        className="inline-flex items-center justify-center text-text-secondary hover:text-text-primary cursor-pointer"
                        title={isAllFilteredSelected ? "Deselect All" : "Select All"}
                      >
                        {isAllFilteredSelected ? (
                          <CheckSquare className="h-4 w-4 text-brand-600" />
                        ) : (
                          <Square className="h-4 w-4" />
                        )}
                      </button>
                    </th>
                    <th className="p-2.5 font-semibold text-text-secondary">Employee</th>
                    <th className="p-2.5 font-semibold text-text-secondary">Position</th>
                    <th className="p-2.5 font-semibold text-text-secondary">Assigned Store</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle">
                  {filteredEmployees.map((emp) => {
                    const isSelected = selectedEmployeeIds.includes(emp.id);
                    const name =
                      emp.fullName || `${emp.firstName ?? ""} ${emp.lastName ?? ""}`.trim() || emp.employeeNo;

                    return (
                      <tr
                        key={emp.id}
                        onClick={() => toggleSelectOne(emp.id)}
                        className={`hover:bg-surface-hover cursor-pointer transition-colors ${
                          isSelected ? "bg-surface-selected" : ""
                        }`}
                      >
                        <td className="p-2.5">
                          <input
                            type="checkbox"
                            checked={isSelected}
                            onChange={() => {}} // Handled by tr onClick
                            className="h-3.5 w-3.5 rounded border-border-default text-brand-600 focus:ring-brand-500 pointer-events-none"
                          />
                        </td>
                        <td className="p-2.5">
                          <p className="font-semibold text-text-primary truncate">{name}</p>
                          <p className="text-[10px] font-mono text-text-muted">{emp.employeeNo}</p>
                        </td>
                        <td className="p-2.5 text-text-secondary truncate">
                          {emp.positionTitle || "—"}
                        </td>
                        <td className="p-2.5 text-text-secondary truncate">
                          {emp.primaryStoreName || "—"}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </div>
        </div>

        {/* Transfer Notes (Optional) */}
        <div>
          <label className="block text-xs font-semibold text-text-primary mb-1">
            Transfer Notes / Remarks <span className="text-text-muted font-normal">(Optional)</span>
          </label>
          <input
            type="text"
            placeholder="e.g. Account consolidation or department realignment"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            disabled={isSubmitting}
            className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none transition-colors"
          />
        </div>
      </form>
    </Modal>
  );
}
