"use client";

import { useState, useMemo } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Store, AlertCircle, Loader2 } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { assignFloatingEmployeeToStore } from "@/lib/queries/plantilla";

export interface AssignStoreModalProps {
  isOpen: boolean;
  onClose: () => void;
  employee: {
    id: string;
    displayName: string;
    employeeNo: string;
    positionTitle?: string | null;
  };
  stores: {
    id: string;
    name: string;
    city: string | null;
    province: string | null;
    code: string | null;
  }[];
  vacantStoreIds?: Set<string>;
  onSuccess?: () => void;
}

export function AssignStoreModal({
  isOpen,
  onClose,
  employee,
  stores,
  vacantStoreIds = new Set(),
  onSuccess,
}: AssignStoreModalProps) {
  const queryClient = useQueryClient();
  const [selectedStoreId, setSelectedStoreId] = useState<string>("");
  const [assignmentType, setAssignmentType] = useState<"Stationary" | "Roving">("Stationary");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Sort stores prioritizing those with open vacancies
  const sortedStores = useMemo(() => {
    return [...stores].sort((a, b) => {
      const aVacant = vacantStoreIds.has(a.id);
      const bVacant = vacantStoreIds.has(b.id);
      if (aVacant && !bVacant) return -1;
      if (!aVacant && bVacant) return 1;
      return a.name.localeCompare(b.name);
    });
  }, [stores, vacantStoreIds]);

  const mutation = useMutation({
    mutationFn: async () => {
      const targetStore = stores.find((s) => s.id === selectedStoreId);
      if (!targetStore) throw new Error("Please select a target store.");

      return assignFloatingEmployeeToStore({
        plantillaId: employee.id,
        storeId: targetStore.id,
        storeName: targetStore.name,
        area: targetStore.province || targetStore.city || null,
        assignmentType,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla", "summary"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla", "account-allocation-kpi"] });
      onSuccess?.();
      onClose();
    },
    onError: (err: Error) => {
      setErrorMessage(err.message || "Failed to assign store to floating employee.");
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);
    if (!selectedStoreId) {
      setErrorMessage("Please select a target store branch.");
      return;
    }
    mutation.mutate();
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Assign Store to Floating Personnel"
      subtitle={`Deploy ${employee.displayName} to active store plantilla`}
      icon={Store}
      maxWidthClass="max-w-md"
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {errorMessage && (
          <div className="flex items-start gap-2.5 rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-200">
            <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
            <span>{errorMessage}</span>
          </div>
        )}

        {/* Floating Personnel Summary */}
        <div className="rounded-lg border border-border-default bg-surface-muted/40 p-3 text-xs space-y-1">
          <div className="flex justify-between">
            <span className="text-text-muted">Floating Personnel:</span>
            <span className="font-semibold text-text-primary">
              {employee.displayName} ({employee.employeeNo})
            </span>
          </div>
          <div className="flex justify-between">
            <span className="text-text-muted">Position / Role:</span>
            <span className="font-semibold text-text-primary">{employee.positionTitle || "General Staff"}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-text-muted">Current Status:</span>
            <span className="inline-flex items-center px-1.5 py-0.2 rounded text-[10px] font-bold bg-blue-100 text-blue-800 dark:bg-blue-950 dark:text-blue-300">
              Floating
            </span>
          </div>
        </div>

        {/* Target Store Dropdown */}
        <div>
          <label className="text-xs font-semibold text-text-primary block mb-1">
            Target Store <span className="text-red-500">*</span>
          </label>
          <select
            value={selectedStoreId}
            onChange={(e) => setSelectedStoreId(e.target.value)}
            required
            className="h-10 w-full rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary outline-none focus:border-brand-500 transition-colors cursor-pointer"
          >
            <option value="">Select target store...</option>
            {sortedStores.map((s) => {
              const isVacant = vacantStoreIds.has(s.id);
              const loc = [s.city, s.province].filter(Boolean).join(", ");
              return (
                <option key={s.id} value={s.id}>
                  {s.name} {loc ? `(${loc})` : ""} {isVacant ? "★ [Open Vacancy]" : ""}
                </option>
              );
            })}
          </select>
          <p className="mt-1 text-[11px] text-text-muted">
            Stores flagged with ★ [Open Vacancy] have approved unfilled capacity slots.
          </p>
        </div>

        {/* Assignment Type */}
        <div>
          <label className="text-xs font-semibold text-text-primary block mb-1">
            Assignment Type <span className="text-red-500">*</span>
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label
              className={`flex items-center gap-2 rounded-lg border p-3 cursor-pointer text-xs transition-colors ${
                assignmentType === "Stationary"
                  ? "border-brand-600 bg-brand-50/50 text-brand-900 font-semibold dark:bg-brand-950/30 dark:text-brand-100"
                  : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover"
              }`}
            >
              <input
                type="radio"
                name="assignmentType"
                value="Stationary"
                checked={assignmentType === "Stationary"}
                onChange={() => setAssignmentType("Stationary")}
                className="h-3.5 w-3.5 text-brand-600 focus:ring-brand-500"
              />
              <span>Stationary</span>
            </label>
            <label
              className={`flex items-center gap-2 rounded-lg border p-3 cursor-pointer text-xs transition-colors ${
                assignmentType === "Roving"
                  ? "border-brand-600 bg-brand-50/50 text-brand-900 font-semibold dark:bg-brand-950/30 dark:text-brand-100"
                  : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover"
              }`}
            >
              <input
                type="radio"
                name="assignmentType"
                value="Roving"
                checked={assignmentType === "Roving"}
                onChange={() => setAssignmentType("Roving")}
                className="h-3.5 w-3.5 text-brand-600 focus:ring-brand-500"
              />
              <span>Roving</span>
            </label>
          </div>
        </div>

        {/* Actions */}
        <div className="flex items-center justify-end gap-2 pt-3 border-t border-border-subtle">
          <button
            type="button"
            onClick={onClose}
            disabled={mutation.isPending}
            className="h-9 rounded-lg border border-border-default bg-surface-base px-3 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={mutation.isPending || !selectedStoreId}
            className="inline-flex h-9 items-center gap-1.5 rounded-lg bg-brand-600 px-4 text-xs font-semibold text-white shadow-2xs hover:bg-brand-700 transition disabled:opacity-50"
          >
            {mutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            <span>Confirm Store Assignment</span>
          </button>
        </div>
      </form>
    </Modal>
  );
}
