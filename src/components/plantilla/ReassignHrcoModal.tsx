"use client";

import { useState } from "react";
import { AlertCircle, CheckCircle2, Loader2, ShieldCheck, User } from "lucide-react";
import { useReassignHrco } from "@/lib/queries/plantilla";
import { Modal } from "@/components/shared/Modal";
import type { ActionModalProps } from "@/types/modal";
import type { HrcoScopeInfo } from "@/components/hr-emploc/useInheritedHrco";
import { formatPersonName } from "@/lib/utils/displayText";

export interface ReassignHrcoModalProps extends ActionModalProps<string> {
  plantillaId: string;
  employeeName: string;
  employeeNo: string;
  currentHrcoName?: string | null;
  availableHrcos: HrcoScopeInfo[];
}

export function ReassignHrcoModal({
  isOpen,
  onClose,
  plantillaId,
  employeeName,
  employeeNo,
  currentHrcoName,
  availableHrcos,
  onSuccess,
}: ReassignHrcoModalProps) {
  const [selectedProfileId, setSelectedProfileId] = useState<string>("");
  const [reason, setReason] = useState<string>("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const mutation = useReassignHrco();

  const normalizedCurrent = (currentHrcoName ?? "").trim().toLowerCase();

  const isCurrentHrco = (hrco: HrcoScopeInfo) => {
    if (!normalizedCurrent) return false;
    return hrco.fullName.trim().toLowerCase() === normalizedCurrent;
  };

  const selectedHrco = availableHrcos.find((h) => h.profileId === selectedProfileId);
  const isDirty = selectedProfileId !== "" || reason.trim() !== "";

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedHrco) {
      setErrorMessage("Please select a new HR Coordinator.");
      return;
    }
    setErrorMessage(null);

    mutation.mutate(
      {
        plantillaId,
        hrcoUserId: selectedHrco.profileId,
        reason: reason.trim() || undefined,
      },
      {
        onSuccess: () => {
          onSuccess?.(selectedHrco.fullName);
          onClose();
        },
        onError: (err: unknown) => {
          const msg = err instanceof Error ? err.message : "Failed to reassign HR Coordinator.";
          setErrorMessage(msg);
        },
      }
    );
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Reassign HR Coordinator"
      subtitle={
        <span className="font-mono text-text-secondary text-xs">
          {employeeNo} • {employeeName}
        </span>
      }
      icon={ShieldCheck}
      isSubmitting={mutation.isPending}
      isDirty={isDirty}
      maxWidthClass="max-w-lg"
    >
      <form onSubmit={handleSubmit} className="space-y-5">
        {/* Current HRCO Banner */}
        <div className="rounded-xl border border-border-default bg-surface-muted/50 p-3.5 flex items-center justify-between gap-3">
          <div className="flex items-center gap-2.5 min-w-0">
            <div className="w-8 h-8 rounded-lg bg-brand-50 border border-brand-200 text-brand-700 flex items-center justify-center shrink-0 dark:bg-brand-950/40 dark:border-brand-800 dark:text-brand-300">
              <User className="w-4 h-4" />
            </div>
            <div className="min-w-0">
              <span className="block text-[11px] font-medium text-text-secondary">
                Current HR Coordinator
              </span>
              <p className="text-xs font-bold text-text-primary truncate">
                {currentHrcoName ? formatPersonName(currentHrcoName) : "Unassigned"}
              </p>
            </div>
          </div>
          <span className="text-[10px] font-semibold text-text-muted uppercase tracking-wider shrink-0 bg-surface px-2 py-0.5 rounded border border-border-subtle">
            Active Assignment
          </span>
        </div>

        {/* HRCO Selector */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <label className="block text-xs font-semibold text-text-secondary">
              Select New HR Coordinator <span className="text-danger-text">*</span>
            </label>
            <span className="text-[11px] text-text-muted">
              {availableHrcos.length} available coordinators
            </span>
          </div>

          <div className="grid gap-2 max-h-60 overflow-y-auto pr-0.5">
            {availableHrcos.map((hrco) => {
              const isCurrent = isCurrentHrco(hrco);
              const isSelected = selectedProfileId === hrco.profileId;

              return (
                <label
                  key={hrco.profileId}
                  className={`flex items-start gap-3 p-3 rounded-xl border text-left transition ${
                    isCurrent
                      ? "opacity-50 cursor-not-allowed bg-surface-muted/40 border-border-subtle"
                      : isSelected
                      ? "border-brand-primary bg-brand-50/20 dark:bg-brand-950/20 ring-1 ring-brand-primary cursor-pointer"
                      : "border-border-default bg-surface hover:bg-surface-muted/60 cursor-pointer"
                  }`}
                >
                  <input
                    type="radio"
                    name="target-hrco"
                    value={hrco.profileId}
                    disabled={isCurrent}
                    checked={isSelected}
                    onChange={() => setSelectedProfileId(hrco.profileId)}
                    className="mt-0.5 text-brand-primary focus:ring-brand-primary"
                  />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-xs font-bold text-text-primary">
                        {formatPersonName(hrco.fullName)}
                      </span>
                      {isCurrent && (
                        <span className="text-[10px] font-semibold text-text-muted bg-surface-muted px-1.5 py-0.2 rounded border border-border-default">
                          Currently Assigned
                        </span>
                      )}
                      {isSelected && !isCurrent && (
                        <span className="text-[10px] font-semibold text-brand-primary bg-brand-50 px-1.5 py-0.2 rounded border border-brand-200 dark:bg-brand-950 dark:border-brand-800">
                          Selected
                        </span>
                      )}
                    </div>
                    {hrco.email && (
                      <span className="block text-[11px] text-text-secondary font-mono mt-0.5 truncate">
                        {hrco.email}
                      </span>
                    )}
                  </div>
                  {isSelected && !isCurrent && (
                    <CheckCircle2 className="h-4 w-4 shrink-0 text-brand-primary mt-0.5" />
                  )}
                </label>
              );
            })}
          </div>
        </div>

        {/* Operational Reason / Notes */}
        <div className="space-y-1.5">
          <label htmlFor="reassign-reason" className="block text-xs font-semibold text-text-secondary">
            Operational Justification / Reason <span className="text-text-muted">(Optional)</span>
          </label>
          <textarea
            id="reassign-reason"
            rows={2}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="e.g. Account portfolio realignment, geographical distribution, workload rebalancing..."
            className="w-full rounded-lg border border-border-default bg-surface px-3 py-2 text-xs text-text-primary placeholder:text-text-muted shadow-xs focus:border-brand-primary focus:outline-hidden"
          />
        </div>

        {/* Error Alert */}
        {errorMessage && (
          <div className="flex items-center gap-2 rounded-lg border border-danger-border bg-danger-bg p-3 text-xs text-danger-text">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <span>{errorMessage}</span>
          </div>
        )}

        {/* Modal Actions */}
        <div className="flex items-center justify-end gap-2 pt-3 border-t border-border-subtle">
          <button
            type="button"
            onClick={onClose}
            disabled={mutation.isPending}
            className="px-3.5 py-2 rounded-lg border border-border-default bg-surface text-xs font-semibold text-text-primary hover:bg-surface-muted transition cursor-pointer disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={mutation.isPending || !selectedHrco || isCurrentHrco(selectedHrco)}
            className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-brand-primary text-white text-xs font-bold hover:bg-brand-secondary transition cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed shadow-xs"
          >
            {mutation.isPending ? (
              <>
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
                <span>Reassigning...</span>
              </>
            ) : (
              <>
                <ShieldCheck className="h-3.5 w-3.5" />
                <span>Confirm Reassignment</span>
              </>
            )}
          </button>
        </div>
      </form>
    </Modal>
  );
}
