"use client";

import { useState, useMemo } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Search, Loader2, UserCheck, AlertCircle } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { fetchPoolEmployees, type WorkforcePoolEmployee } from "@/lib/queries/workforcePool";
import { assignRelieverCoverage } from "@/lib/queries/plantilla";

export interface AssignRelieverModalProps {
  isOpen: boolean;
  onClose: () => void;
  employee: {
    id: string;
    displayName: string;
    employeeNo: string;
    storeId?: string | null;
    storeName?: string | null;
  };
  accountId: string;
  onSuccess?: () => void;
}

export function AssignRelieverModal({
  isOpen,
  onClose,
  employee,
  accountId,
  onSuccess,
}: AssignRelieverModalProps) {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const [selectedReliever, setSelectedReliever] = useState<WorkforcePoolEmployee | null>(null);
  const [startDate, setStartDate] = useState(() => new Date().toISOString().substring(0, 10));
  const [endDate, setEndDate] = useState(() => {
    const d = new Date();
    d.setDate(d.getDate() + 14);
    return d.toISOString().substring(0, 10);
  });
  const [notes, setNotes] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Fetch Available relievers from Moses HQ pool
  const poolEmployeesQuery = useQuery({
    queryKey: ["workforce-pool", "available-relievers"],
    queryFn: () => fetchPoolEmployees({ availability: "Available" }),
    enabled: isOpen,
    staleTime: 30000,
  });

  const filteredRelievers = useMemo(() => {
    const list = poolEmployeesQuery.data ?? [];
    if (!search.trim()) return list;
    const q = search.toLowerCase().trim();
    return list.filter(
      (r) =>
        r.employeeName.toLowerCase().includes(q) ||
        r.employeeNo.toLowerCase().includes(q) ||
        (r.position && r.position.toLowerCase().includes(q)) ||
        (r.poolTypeName && r.poolTypeName.toLowerCase().includes(q)),
    );
  }, [poolEmployeesQuery.data, search]);

  const mutation = useMutation({
    mutationFn: async () => {
      if (!selectedReliever) throw new Error("Please select a reliever.");
      if (!employee.storeId) throw new Error("On-leave employee has no assigned store.");

      return assignRelieverCoverage({
        employeeId: selectedReliever.id,
        poolTypeId: selectedReliever.poolTypeId,
        coveredPlantillaId: employee.id,
        assignedAccountId: accountId,
        assignedStoreId: employee.storeId,
        startDate,
        endDate,
        notes: notes.trim() || `Covering ${employee.displayName} (${employee.employeeNo})`,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["workforce-pool"] });
      queryClient.invalidateQueries({ queryKey: ["v_workforce_store_temporary_coverage"] });
      onSuccess?.();
      onClose();
    },
    onError: (err: Error) => {
      setErrorMessage(err.message || "Failed to assign reliever.");
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);
    if (!selectedReliever) {
      setErrorMessage("Please select an available reliever from Moses HQ Pool.");
      return;
    }
    if (!employee.storeId) {
      setErrorMessage("The on-leave employee does not have a primary store assignment.");
      return;
    }
    mutation.mutate();
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Assign Reliever (Moses HQ Pool)"
      subtitle={`Temporary coverage for ${employee.displayName} (${employee.employeeNo})`}
      icon={UserCheck}
      maxWidthClass="max-w-xl"
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {errorMessage && (
          <div className="flex items-start gap-2.5 rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-200">
            <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
            <span>{errorMessage}</span>
          </div>
        )}

        {/* Target Employee & Store Summary */}
        <div className="rounded-lg border border-border-default bg-surface-muted/40 p-3 text-xs space-y-1">
          <div className="flex justify-between">
            <span className="text-text-muted">On-Leave Member:</span>
            <span className="font-semibold text-text-primary">{employee.displayName}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-text-muted">Assigned Store:</span>
            <span className="font-semibold text-text-primary">{employee.storeName || "—"}</span>
          </div>
        </div>

        {/* Reliever Search & List */}
        <div className="space-y-2">
          <label className="text-xs font-semibold text-text-primary">
            Select Available Reliever <span className="text-red-500">*</span>
          </label>
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search by reliever name, ID, or pool..."
              className="h-9 w-full rounded-lg border border-border-default bg-surface-base pl-9 pr-3 text-xs text-text-primary outline-none focus:border-brand-500 transition-colors"
            />
          </div>

          <div className="max-h-48 overflow-y-auto rounded-lg border border-border-default divide-y divide-border-subtle bg-surface-base">
            {poolEmployeesQuery.isLoading ? (
              <div className="flex items-center justify-center p-6 text-xs text-text-muted">
                <Loader2 className="h-4 w-4 animate-spin mr-2" />
                <span>Loading available relievers...</span>
              </div>
            ) : filteredRelievers.length === 0 ? (
              <div className="p-6 text-center text-xs text-text-muted">
                No available relievers found in Moses HQ Pool.
              </div>
            ) : (
              filteredRelievers.map((reliever) => {
                const isSelected = selectedReliever?.id === reliever.id;
                return (
                  <button
                    key={reliever.id}
                    type="button"
                    onClick={() => {
                      setSelectedReliever(reliever);
                      setErrorMessage(null);
                    }}
                    className={`w-full flex items-center justify-between p-2.5 text-left text-xs transition-colors cursor-pointer ${
                      isSelected
                        ? "bg-brand-50/80 text-brand-900 font-semibold dark:bg-brand-950/40 dark:text-brand-100"
                        : "hover:bg-surface-hover text-text-primary"
                    }`}
                  >
                    <div>
                      <div className="font-bold">{reliever.employeeName}</div>
                      <div className="text-[11px] text-text-muted mt-0.5">
                        {reliever.employeeNo} • {reliever.position || "General Staff"} • {reliever.poolTypeName}
                      </div>
                    </div>
                    {isSelected && (
                      <span className="inline-flex items-center rounded-full bg-brand-600 px-2 py-0.5 text-[10px] font-bold text-white">
                        Selected
                      </span>
                    )}
                  </button>
                );
              })
            )}
          </div>
        </div>

        {/* Date Range */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="text-xs font-semibold text-text-primary block mb-1">
              Start Date <span className="text-red-500">*</span>
            </label>
            <input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              required
              className="h-9 w-full rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary outline-none focus:border-brand-500"
            />
          </div>
          <div>
            <label className="text-xs font-semibold text-text-primary block mb-1">
              End Date <span className="text-red-500">*</span>
            </label>
            <input
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              required
              className="h-9 w-full rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary outline-none focus:border-brand-500"
            />
          </div>
        </div>

        {/* Optional Notes */}
        <div>
          <label className="text-xs font-semibold text-text-primary block mb-1">
            Coverage Notes / Remarks (Optional)
          </label>
          <textarea
            rows={2}
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="Special instructions or reason for coverage..."
            className="w-full rounded-lg border border-border-default bg-surface-base p-2.5 text-xs text-text-primary outline-none focus:border-brand-500"
          />
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
            disabled={mutation.isPending || !selectedReliever}
            className="inline-flex h-9 items-center gap-1.5 rounded-lg bg-brand-600 px-4 text-xs font-semibold text-white shadow-2xs hover:bg-brand-700 transition disabled:opacity-50"
          >
            {mutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            <span>Deploy Reliever</span>
          </button>
        </div>
      </form>
    </Modal>
  );
}
