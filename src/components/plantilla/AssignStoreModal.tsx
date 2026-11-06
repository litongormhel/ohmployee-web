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
    floatingDays?: number;
  };
  stores: {
    id: string;
    name: string;
    city: string | null;
    province: string | null;
    code: string | null;
    hcFilled?: number;
    hcTotal?: number;
    openSlots?: number;
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
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Strictly filter to stores that have open or available slots (hc_filled < hc_total or openSlots > 0).
  // Fully occupied stores (e.g., 1/1, 2/2) are filtered out and hidden to prevent over-allocation.
  const availableStores = useMemo(() => {
    return stores.filter((s) => {
      if (s.openSlots !== undefined) {
        return s.openSlots > 0;
      }
      if (s.hcTotal !== undefined && s.hcFilled !== undefined) {
        return s.hcFilled < s.hcTotal;
      }
      return vacantStoreIds.has(s.id);
    });
  }, [stores, vacantStoreIds]);

  // Sort available stores prioritizing higher open slot count then alphabetical
  const sortedStores = useMemo(() => {
    return [...availableStores].sort((a, b) => {
      const aSlots =
        a.openSlots ??
        (a.hcTotal !== undefined && a.hcFilled !== undefined
          ? Math.max(0, a.hcTotal - a.hcFilled)
          : 0);
      const bSlots =
        b.openSlots ??
        (b.hcTotal !== undefined && b.hcFilled !== undefined
          ? Math.max(0, b.hcTotal - b.hcFilled)
          : 0);
      if (aSlots !== bSlots) return bSlots - aSlots;
      const aVacant = vacantStoreIds.has(a.id);
      const bVacant = vacantStoreIds.has(b.id);
      if (aVacant && !bVacant) return -1;
      if (!aVacant && bVacant) return 1;
      return a.name.localeCompare(b.name);
    });
  }, [availableStores, vacantStoreIds]);

  const mutation = useMutation({
    mutationFn: async () => {
      const targetStore = stores.find((s) => s.id === selectedStoreId);
      if (!targetStore) throw new Error("Please select a target store.");

      return assignFloatingEmployeeToStore({
        plantillaId: employee.id,
        storeId: targetStore.id,
        storeName: targetStore.name,
        area: targetStore.province || targetStore.city || null,
        assignmentType: "Stationary",
        vcode: targetStore.code || null,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla", "detail", employee.id] });
      queryClient.invalidateQueries({ queryKey: ["plantilla-detail"] });
      queryClient.invalidateQueries({ queryKey: ["web-plantilla-summary"] });
      queryClient.invalidateQueries({ queryKey: ["store-staffing"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
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
        <div className="rounded-lg border border-border-default bg-surface-muted/40 p-3 text-xs space-y-1.5">
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
          <div className="flex justify-between items-center">
            <span className="text-text-muted">Current Status:</span>
            <span className="inline-flex items-center px-1.5 py-0.2 rounded text-[10px] font-bold bg-blue-100 text-blue-800 dark:bg-blue-950 dark:text-blue-300">
              Floating
            </span>
          </div>
          {employee.floatingDays !== undefined && (
            <div className="flex justify-between items-center pt-1 border-t border-border-subtle">
              <span className="text-text-muted">DOLE Compliance Tracking:</span>
              <span className="font-semibold text-text-primary font-mono text-[11px]">
                {employee.floatingDays} days elapsed (DOLE 180d limit)
              </span>
            </div>
          )}
        </div>

        {/* Target Store Dropdown */}
        <div>
          <label className="text-xs font-semibold text-text-primary block mb-1">
            Target Store <span className="text-red-500">*</span>
          </label>
          {sortedStores.length === 0 ? (
            <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800 dark:border-amber-800 dark:bg-amber-950/50 dark:text-amber-200 space-y-1">
              <p className="font-semibold flex items-center gap-1.5">
                <AlertCircle className="h-3.5 w-3.5 shrink-0" />
                No Stores with Open Slots Available
              </p>
              <p className="text-[11px] text-amber-700 dark:text-amber-300">
                All stores under this account are currently fully occupied (1/1). To prevent over-allocation, floating personnel can only be assigned to stores with open slots (hc_filled &lt; hc_total).
              </p>
            </div>
          ) : (
            <>
              <select
                value={selectedStoreId}
                onChange={(e) => setSelectedStoreId(e.target.value)}
                required
                className="h-10 w-full rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary outline-none focus:border-brand-500 transition-colors cursor-pointer"
              >
                <option value="">Select target store with available slots...</option>
                {sortedStores.map((s) => {
                  const loc = [s.city, s.province].filter(Boolean).join(", ");
                  const slotLabel =
                    s.hcFilled !== undefined && s.hcTotal !== undefined
                      ? ` • ${s.hcFilled}/${s.hcTotal} slots (${Math.max(0, s.hcTotal - s.hcFilled)} open)`
                      : s.openSlots !== undefined
                      ? ` • ${s.openSlots} open slot${s.openSlots > 1 ? "s" : ""}`
                      : vacantStoreIds.has(s.id)
                      ? " • ★ [Open Vacancy]"
                      : "";

                  return (
                    <option key={s.id} value={s.id}>
                      {s.name} {loc ? `(${loc})` : ""}{slotLabel}
                    </option>
                  );
                })}
              </select>
              <p className="mt-1 text-[11px] text-text-muted">
                Restricted strictly to stores with available capacity (hc_filled &lt; hc_total) to prevent over-allocation.
              </p>
            </>
          )}
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
