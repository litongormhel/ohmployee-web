"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { RotateCcw, AlertCircle, Info, Loader2 } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { updatePlantillaEmploymentStatus } from "@/lib/queries/plantilla";

export interface ReturnToActiveModalProps {
  isOpen: boolean;
  onClose: () => void;
  employee: {
    id: string;
    displayName: string;
    employeeNo: string;
    storeName?: string | null;
  };
  assignedReliever?: {
    id: string;
    name: string;
    employeeNumber: string;
  } | null;
  onSuccess?: () => void;
}

export function ReturnToActiveModal({
  isOpen,
  onClose,
  employee,
  assignedReliever,
  onSuccess,
}: ReturnToActiveModalProps) {
  const queryClient = useQueryClient();
  const [actualReturnDate, setActualReturnDate] = useState(() =>
    new Date().toISOString().substring(0, 10),
  );
  const [remarks, setRemarks] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const mutation = useMutation({
    mutationFn: async () => {
      const formattedRemarks = [
        actualReturnDate ? `Actual Return: ${actualReturnDate}` : null,
        remarks.trim() || null,
      ]
        .filter(Boolean)
        .join(" | ");

      return updatePlantillaEmploymentStatus({
        plantillaId: employee.id,
        targetStatus: "Active",
        remarks: formattedRemarks || undefined,
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
      setErrorMessage(err.message || "Failed to return employee to Active status.");
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);
    mutation.mutate();
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Return to Active Status"
      subtitle={`Confirm return for ${employee.displayName}`}
      icon={RotateCcw}
      maxWidthClass="max-w-md"
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {errorMessage && (
          <div className="flex items-start gap-2.5 rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-200">
            <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
            <span>{errorMessage}</span>
          </div>
        )}

        {/* Employee Summary Card */}
        <div className="rounded-lg border border-border-default bg-surface-muted/40 p-3 text-xs space-y-1">
          <div className="flex justify-between">
            <span className="text-text-muted">Employee:</span>
            <span className="font-semibold text-text-primary">
              {employee.displayName} ({employee.employeeNo})
            </span>
          </div>
          <div className="flex justify-between">
            <span className="text-text-muted">Store Branch:</span>
            <span className="font-semibold text-text-primary">{employee.storeName || "—"}</span>
          </div>
        </div>

        {/* Reliever Auto-Release Notice */}
        {assignedReliever ? (
          <div className="flex items-start gap-2.5 rounded-lg border border-amber-200 bg-amber-50/80 p-3 text-xs text-amber-800 dark:border-amber-800 dark:bg-amber-950/40 dark:text-amber-200">
            <Info className="h-4 w-4 shrink-0 mt-0.5 text-amber-600 dark:text-amber-400" />
            <div>
              <p className="font-bold">Reliever Auto-Release Notice</p>
              <p className="mt-0.5 leading-relaxed text-[11px]">
                A reliever (<span className="font-semibold">{assignedReliever.name}</span> • {assignedReliever.employeeNumber}) is currently assigned to cover this employee. Confirming will automatically unassign the reliever and return their status to <strong className="font-bold">Available</strong> in the Moses HQ Pool.
              </p>
            </div>
          </div>
        ) : (
          <div className="flex items-start gap-2 rounded-lg border border-border-default bg-surface-muted/30 p-2.5 text-xs text-text-secondary">
            <Info className="h-3.5 w-3.5 shrink-0 mt-0.5 text-text-muted" />
            <span>No Moses HQ reliever is currently linked to this leave coverage.</span>
          </div>
        )}

        {/* Actual Return Date Picker */}
        <div>
          <label className="text-xs font-semibold text-text-primary block mb-1">
            Actual Return Date <span className="text-red-500">*</span>
          </label>
          <input
            type="date"
            value={actualReturnDate}
            onChange={(e) => setActualReturnDate(e.target.value)}
            required
            className="h-9 w-full rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary outline-none focus:border-brand-500 transition-colors"
          />
        </div>

        {/* Optional Remarks */}
        <div>
          <label className="text-xs font-semibold text-text-primary block mb-1">
            Return Remarks / Handover Notes (Optional)
          </label>
          <textarea
            rows={2}
            value={remarks}
            onChange={(e) => setRemarks(e.target.value)}
            placeholder="e.g. Fit to work clearance verified..."
            className="w-full rounded-lg border border-border-default bg-surface-base p-2.5 text-xs text-text-primary outline-none focus:border-brand-500 transition-colors"
          />
        </div>

        {/* Modal Actions */}
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
            disabled={mutation.isPending}
            className="inline-flex h-9 items-center gap-1.5 rounded-lg bg-emerald-600 px-4 text-xs font-semibold text-white shadow-2xs hover:bg-emerald-700 transition disabled:opacity-50"
          >
            {mutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            <span>Confirm Return to Active</span>
          </button>
        </div>
      </form>
    </Modal>
  );
}
