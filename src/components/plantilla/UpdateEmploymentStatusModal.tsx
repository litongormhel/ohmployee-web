"use client";

import { useState } from "react";
import { AlertCircle, Calendar, CheckCircle2, Clock, Loader2, PauseCircle, UserCheck, X } from "lucide-react";
import {
  useUpdateEmploymentStatus,
  type EmploymentStatusTarget,
} from "@/lib/queries/plantilla";

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
    colorClass: "text-emerald-600 border-emerald-200 bg-emerald-50/60",
  },
  {
    value: "On Leave",
    label: "On Leave",
    description: "Approved medical, maternity, or authorized leave; slot flagged for reliever coverage",
    icon: Clock,
    colorClass: "text-amber-600 border-amber-200 bg-amber-50/60",
  },
  {
    value: "Floating",
    label: "Floating",
    description: "Temporarily unassigned/floating inactive; triggers deactivation request readiness",
    icon: PauseCircle,
    colorClass: "text-purple-600 border-purple-200 bg-purple-50/60",
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

  if (!isOpen) return null;

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
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="employment-status-modal-title"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-in fade-in duration-150"
    >
      <div className="relative w-full max-w-lg rounded-xl border border-gray-200 bg-white shadow-2xl overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4 bg-blue-50/70">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-blue-100 text-blue-700 border border-blue-200">
              <UserCheck className="h-5 w-5" />
            </div>
            <div>
              <h2 id="employment-status-modal-title" className="text-base font-semibold text-gray-900">
                Update Employment Status
              </h2>
              <p className="text-xs text-gray-500 font-mono">
                {employeeNo} &bull; {employeeName} &bull; Current: {currentStatus || "Active"}
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg p-1.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition"
            aria-label="Close modal"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Form Body */}
        <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto p-6 space-y-5">
          {/* Target Status Radios */}
          <div className="space-y-2">
            <label className="block text-xs font-semibold uppercase tracking-wider text-gray-700">
              Select New Employment Status <span className="text-red-500">*</span>
            </label>
            <div className="grid gap-2">
              {STATUS_OPTIONS.map((opt) => {
                const IconComponent = opt.icon;
                const isSelected = targetStatus === opt.value;
                return (
                  <label
                    key={opt.value}
                    className={`flex items-start gap-3 p-3 rounded-lg border cursor-pointer transition ${
                      isSelected
                        ? "border-blue-500 bg-blue-50/50 ring-1 ring-blue-500"
                        : "border-gray-200 hover:border-gray-300 hover:bg-gray-50/50"
                    }`}
                  >
                    <input
                      type="radio"
                      name="targetStatus"
                      value={opt.value}
                      checked={isSelected}
                      onChange={() => setTargetStatus(opt.value)}
                      className="mt-0.5 text-blue-600 focus:ring-blue-500"
                    />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="text-xs font-semibold text-gray-900">{opt.label}</span>
                        {isSelected && (
                          <span className="text-[10px] font-medium text-blue-700 bg-blue-100 px-1.5 py-0.2 rounded border border-blue-200">
                            Selected
                          </span>
                        )}
                      </div>
                      <p className="mt-0.5 text-[11px] text-gray-500 leading-normal">
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
            <div className="rounded-lg border border-amber-200 bg-amber-50/50 p-4 space-y-3.5 animate-in fade-in duration-150">
              <div className="flex items-start gap-2">
                <Clock className="h-4 w-4 text-amber-600 mt-0.5 shrink-0" />
                <p className="text-xs text-amber-900 leading-relaxed font-medium">
                  On-Leave personnel remain in the active directory roster with an On Leave indicator, enabling Moses HQ Reliever Endorsements.
                </p>
              </div>

              <div className="space-y-1">
                <label htmlFor="leave-reason" className="block text-xs font-medium text-gray-700">
                  Leave Reason / Type
                </label>
                <select
                  id="leave-reason"
                  value={leaveReason}
                  onChange={(e) => setLeaveReason(e.target.value)}
                  className="w-full rounded-md border border-gray-300 bg-white px-3 py-1.5 text-xs text-gray-900 shadow-xs focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
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
                <label htmlFor="expected-return" className="block text-xs font-medium text-gray-700">
                  Expected Return Date
                </label>
                <div className="relative">
                  <input
                    id="expected-return"
                    type="date"
                    value={expectedReturnDate}
                    onChange={(e) => setExpectedReturnDate(e.target.value)}
                    className="w-full rounded-md border border-gray-300 bg-white px-3 py-1.5 pl-8 text-xs text-gray-900 shadow-xs focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
                  />
                  <Calendar className="pointer-events-none absolute left-2.5 top-2 h-3.5 w-3.5 text-gray-400" />
                </div>
              </div>
            </div>
          )}

          {/* Conditional Fields: Floating */}
          {targetStatus === "Floating" && (
            <div className="rounded-lg border border-purple-200 bg-purple-50/50 p-4 space-y-3 animate-in fade-in duration-150">
              <div className="flex items-start gap-2">
                <PauseCircle className="h-4 w-4 text-purple-600 mt-0.5 shrink-0" />
                <p className="text-xs text-purple-900 leading-relaxed font-medium">
                  Setting this employee to Floating moves their record to the Inactive tab with a Floating designation. You will be able to file a formal Deactivation Request subsequently.
                </p>
              </div>
            </div>
          )}

          {/* Conditional Fields: Active Return */}
          {targetStatus === "Active" && normalizedCurrent === "on leave" && (
            <div className="rounded-lg border border-emerald-200 bg-emerald-50/50 p-4 space-y-2 animate-in fade-in duration-150">
              <div className="flex items-start gap-2">
                <CheckCircle2 className="h-4 w-4 text-emerald-600 mt-0.5 shrink-0" />
                <p className="text-xs text-emerald-900 leading-relaxed font-medium">
                  Returning to Active status will restore normal duty and release any temporary reliever coverage assignment linked to this slot.
                </p>
              </div>
            </div>
          )}

          {/* General Remarks / Notes */}
          <div className="space-y-1.5">
            <label htmlFor="status-remarks" className="block text-xs font-semibold uppercase tracking-wider text-gray-700">
              Operational Remarks (Optional)
            </label>
            <textarea
              id="status-remarks"
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              rows={2}
              placeholder="Add optional notes or documentation details..."
              className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-xs text-gray-900 placeholder:text-gray-400 shadow-xs focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
            />
          </div>

          {/* Error Message */}
          {errorMessage && (
            <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-700 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 text-red-500 mt-0.5" />
              <span>{errorMessage}</span>
            </div>
          )}

          {/* Action Footer */}
          <div className="flex items-center justify-end gap-2.5 pt-2 border-t border-gray-100">
            <button
              type="button"
              onClick={onClose}
              disabled={mutation.isPending}
              className="rounded-lg border border-gray-300 bg-white px-4 py-2 text-xs font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50 transition"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={mutation.isPending}
              className="inline-flex items-center gap-1.5 rounded-lg bg-blue-600 px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-blue-700 disabled:opacity-50 transition cursor-pointer"
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
      </div>
    </div>
  );
}
