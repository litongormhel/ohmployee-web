"use client";

import { useState } from "react";
import { AlertCircle, Calendar, CheckCircle2, Clock, Loader2, PauseCircle, UserCheck } from "lucide-react";
import {
  useUpdateEmploymentStatus,
  type EmploymentStatusTarget,
} from "@/lib/queries/plantilla";
import { Modal } from "@/components/shared/Modal";

export interface UpdateEmploymentStatusModalProps {
  isOpen: boolean;
  onClose: () => void;
  plantillaId: string;
  employeeName: string;
  employeeNo: string;
  currentStatus?: string | null;
  onSuccess?: () => void;
}

const STATUS_OPTIONS: {
  value: EmploymentStatusTarget;
  label: string;
  description: string;
  icon: typeof UserCheck;
  colorClass: string;
}[] = [
  {
    value: "Active",
    label: "Active",
    description: "Employee is fully active and performing duties in assigned slot",
    icon: CheckCircle2,
    colorClass: "text-pct-good-text border-pct-good-border bg-pct-good-bg",
  },
  {
    value: "On Leave",
    label: "On Leave",
    description: "Approved medical, maternity, or authorized leave; slot flagged for reliever coverage",
    icon: Clock,
    colorClass: "text-pct-warn-text border-pct-warn-border bg-pct-warn-bg",
  },
  {
    value: "Floating",
    label: "Floating",
    description: "Temporarily unassigned/floating inactive; triggers deactivation request readiness",
    icon: PauseCircle,
    colorClass: "text-text-primary border-border-default bg-surface-muted",
  },
];

export function UpdateEmploymentStatusModal({
  isOpen,
  onClose,
  plantillaId,
  employeeName,
  employeeNo,
  currentStatus,
  onSuccess,
}: UpdateEmploymentStatusModalProps) {
  const normalizedCurrent = (currentStatus ?? "").trim().toLowerCase();
  const defaultTarget: EmploymentStatusTarget =
    normalizedCurrent === "on leave"
      ? "Active"
      : normalizedCurrent === "active"
      ? "On Leave"
      : "Active";

  const [targetStatus, setTargetStatus] = useState<EmploymentStatusTarget>(defaultTarget);
  const [leaveReason, setLeaveReason] = useState<string>("");
  const [expectedReturnDate, setExpectedReturnDate] = useState<string>("");
  const [remarks, setRemarks] = useState<string>("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const mutation = useUpdateEmploymentStatus();

  const isDirty =
    targetStatus !== defaultTarget ||
    leaveReason !== "" ||
    expectedReturnDate !== "" ||
    remarks.trim() !== "";

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    mutation.mutate(
      {
        plantillaId,
        targetStatus,
        reason: leaveReason.trim() || undefined,
        remarks: remarks.trim() || undefined,
        expectedReturnDate: expectedReturnDate || undefined,
      },
      {
        onSuccess: () => {
          onSuccess?.();
          onClose();
        },
        onError: (err) => {
          setErrorMessage(err.message || "Failed to update employment status.");
        },
      },
    );
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Update Employment Status"
      subtitle={
        <span className="font-mono text-text-secondary text-xs">
          {employeeNo} • {employeeName} • Current: {currentStatus || "Active"}
        </span>
      }
      icon={UserCheck}
      isSubmitting={mutation.isPending}
      isDirty={isDirty}
      maxWidthClass="max-w-lg"
    >
      <form onSubmit={handleSubmit} className="space-y-5">
        {/* Target Status Radios */}
        <div className="space-y-2">
          <label className="block text-xs font-semibold text-text-secondary">
            Select New Employment Status <span className="text-danger-text">*</span>
          </label>
          <div className="grid gap-2">
            {STATUS_OPTIONS.map((opt) => {
              const IconComponent = opt.icon;
              const isSelected = targetStatus === opt.value;
              return (
                <label
                  key={opt.value}
                  className={`flex items-start gap-3 p-3 rounded-lg border cursor-pointer transition-colors ${
                    isSelected
                      ? "border-brand-primary bg-surface-selected ring-1 ring-brand-primary"
                      : "border-border-default hover:border-border-strong hover:bg-surface-hover"
                  }`}
                >
                  <input
                    type="radio"
                    name="targetStatus"
                    value={opt.value}
                    checked={isSelected}
                    onChange={() => setTargetStatus(opt.value)}
                    className="mt-0.5 text-brand-primary focus:ring-brand-primary"
                  />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-xs font-semibold text-text-primary">{opt.label}</span>
                      {isSelected && (
                        <span className="text-[10px] font-medium text-brand-primary bg-surface px-1.5 py-0.2 rounded border border-border-default">
                          Selected
                        </span>
                      )}
                    </div>
                    <p className="mt-0.5 text-[11px] text-text-secondary leading-normal">
                      {opt.description}
                    </p>
                  </div>
                  <IconComponent className={`h-4 w-4 shrink-0 mt-0.5 ${opt.colorClass.split(" ")[0]}`} />
                </label>
              );
            })}
          </div>
        </div>

        {/* Conditional Fields: On Leave */}
        {targetStatus === "On Leave" && (
          <div className="rounded-lg border border-border-default bg-surface-muted p-4 space-y-3.5 animate-in fade-in duration-150">
            <div className="flex items-start gap-2">
              <Clock className="h-4 w-4 text-pct-warn-text mt-0.5 shrink-0" />
              <p className="text-xs text-text-primary leading-relaxed font-medium">
                On-Leave personnel remain in the active directory roster with an On Leave indicator, enabling Moses HQ Reliever Endorsements.
              </p>
            </div>

            <div className="space-y-1">
              <label htmlFor="leave-reason" className="block text-xs font-medium text-text-secondary">
                Leave Reason / Type
              </label>
              <select
                id="leave-reason"
                value={leaveReason}
                onChange={(e) => setLeaveReason(e.target.value)}
                className="w-full rounded-md border border-border-default bg-surface px-3 py-1.5 text-xs text-text-primary shadow-xs focus:border-brand-primary focus:outline-hidden"
              >
                <option value="">Select reason...</option>
                <option value="Sick / Medical Leave">Sick / Medical Leave</option>
                <option value="Maternity / Paternity Leave">Maternity / Paternity Leave</option>
                <option value="Vacation Leave">Vacation Leave</option>
                <option value="Emergency Family Leave">Emergency Family Leave</option>
                <option value="Other Authorized Leave">Other Authorized Leave</option>
              </select>
            </div>

            <div className="space-y-1">
              <label htmlFor="expected-return" className="block text-xs font-medium text-text-secondary">
                Expected Return Date
              </label>
              <div className="relative">
                <input
                  id="expected-return"
                  type="date"
                  value={expectedReturnDate}
                  onChange={(e) => setExpectedReturnDate(e.target.value)}
                  className="w-full rounded-md border border-border-default bg-surface px-3 py-1.5 pl-8 text-xs text-text-primary shadow-xs focus:border-brand-primary focus:outline-hidden"
                />
                <Calendar className="pointer-events-none absolute left-2.5 top-2 h-3.5 w-3.5 text-text-muted" />
              </div>
            </div>
          </div>
        )}

        {/* Conditional Fields: Floating */}
        {targetStatus === "Floating" && (
          <div className="rounded-lg border border-border-default bg-surface-muted p-4 space-y-3 animate-in fade-in duration-150">
            <div className="flex items-start gap-2">
              <PauseCircle className="h-4 w-4 text-text-secondary mt-0.5 shrink-0" />
              <p className="text-xs text-text-primary leading-relaxed font-medium">
                Setting this employee to Floating moves their record to the Inactive tab with a Floating designation. You will be able to file a formal Deactivation Request subsequently.
              </p>
            </div>
          </div>
        )}

        {/* Conditional Fields: Active Return */}
        {targetStatus === "Active" && normalizedCurrent === "on leave" && (
          <div className="rounded-lg border border-border-default bg-surface-muted p-4 space-y-2 animate-in fade-in duration-150">
            <div className="flex items-start gap-2">
              <CheckCircle2 className="h-4 w-4 text-pct-good-text mt-0.5 shrink-0" />
              <p className="text-xs text-text-primary leading-relaxed font-medium">
                Returning to Active status will restore normal duty and release any temporary reliever coverage assignment linked to this slot.
              </p>
            </div>
          </div>
        )}

        {/* General Remarks / Notes */}
        <div className="space-y-1.5">
          <label htmlFor="status-remarks" className="block text-xs font-semibold text-text-secondary">
            Operational Remarks (Optional)
          </label>
          <textarea
            id="status-remarks"
            value={remarks}
            onChange={(e) => setRemarks(e.target.value)}
            rows={2}
            placeholder="Add optional notes or documentation details..."
            className="w-full rounded-lg border border-border-default bg-surface px-3 py-2 text-xs text-text-primary placeholder:text-text-muted shadow-xs focus:border-brand-primary focus:outline-hidden"
          />
        </div>

        {/* Error Message */}
        {errorMessage && (
          <div className="rounded-lg border border-danger-border bg-danger-bg p-3 text-xs text-danger-text flex items-start gap-2">
            <AlertCircle className="h-4 w-4 shrink-0 text-danger-text mt-0.5" />
            <span>{errorMessage}</span>
          </div>
        )}

        {/* Action Footer */}
        <div className="flex items-center justify-end gap-2.5 pt-3 border-t border-border-default">
          <button
            type="button"
            onClick={onClose}
            disabled={mutation.isPending}
            className="rounded-lg border border-border-default bg-surface px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary disabled:opacity-50 transition-colors cursor-pointer"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={mutation.isPending}
            className="inline-flex items-center gap-1.5 rounded-lg bg-brand-button px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-brand-secondary disabled:opacity-50 transition-colors cursor-pointer"
          >
            {mutation.isPending ? (
              <>
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
                Updating Status...
              </>
            ) : (
              `Set Status to ${targetStatus}`
            )}
          </button>
        </div>
      </form>
    </Modal>
  );
}
