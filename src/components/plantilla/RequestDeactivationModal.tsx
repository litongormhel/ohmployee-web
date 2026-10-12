"use client";

import { useState } from "react";
import { AlertCircle, Clock, FileText, Loader2, ShieldAlert, X } from "lucide-react";
import { useCreateDeactivationRequest } from "@/lib/queries/plantilla";

export interface RequestDeactivationModalProps {
  isOpen: boolean;
  onClose: () => void;
  plantillaId: string;
  employeeName: string;
  employeeNo: string;
  currentStatus?: string | null;
  onSuccess?: () => void;
}

const DEACTIVATION_REASONS = [
  "Completed 15-day clearance offboarding period",
  "Prolonged AWOL with documented abandonment notice",
  "Contract completed and company assets surrendered",
  "Administrative dismissal finalized",
  "Other authorized management rationale",
];

export function RequestDeactivationModal({
  isOpen,
  onClose,
  plantillaId,
  employeeName,
  employeeNo,
  currentStatus,
  onSuccess,
}: RequestDeactivationModalProps) {
  const [reason, setReason] = useState<string>(DEACTIVATION_REASONS[0]);
  const [remarks, setRemarks] = useState<string>("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const mutation = useCreateDeactivationRequest();

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!remarks.trim()) {
      setErrorMessage("Mandatory remarks/justification are required to submit a deactivation request.");
      return;
    }

    mutation.mutate(
      {
        plantillaId,
        reason,
        remarks: remarks.trim(),
      },
      {
        onSuccess: () => {
          onSuccess?.();
          onClose();
        },
        onError: (err) => {
          setErrorMessage(err.message || "Failed to submit deactivation request.");
        },
      },
    );
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="deactivation-modal-title"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-in fade-in duration-150"
    >
      <div className="relative w-full max-w-lg rounded-xl border border-gray-200 bg-white shadow-2xl overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4 bg-amber-50/70">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-amber-100 text-amber-700 border border-amber-200">
              <ShieldAlert className="h-5 w-5" />
            </div>
            <div>
              <h2 id="deactivation-modal-title" className="text-base font-semibold text-gray-900">
                Request Personnel Deactivation
              </h2>
              <p className="text-xs text-gray-500 font-mono">
                {employeeNo} &bull; {employeeName} &bull; Status: {currentStatus || "Inactive"}
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
          {/* 15-day clearance policy notice */}
          <div className="rounded-lg border border-amber-200 bg-amber-50/80 p-3.5 flex items-start gap-3">
            <Clock className="h-5 w-5 shrink-0 text-amber-600 mt-0.5" />
            <div className="text-xs text-amber-900 leading-relaxed">
              <span className="font-semibold">Standard 15-Day Clearance Notice:</span>
              <p className="mt-0.5 text-amber-800">
                Standard operating policy mandates a 15-day clearance and asset recovery window before final
                Super Admin / Head Admin deactivation approval. Submitting this request places the personnel
                record in the <strong>Approvals Center</strong> queue.
              </p>
            </div>
          </div>

          {/* Deactivation Reason Category */}
          <div className="space-y-1.5">
            <label htmlFor="deactivation-reason" className="block text-xs font-semibold uppercase tracking-wider text-gray-700">
              Deactivation Justification <span className="text-red-500">*</span>
            </label>
            <select
              id="deactivation-reason"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-xs text-gray-900 shadow-xs focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
            >
              {DEACTIVATION_REASONS.map((r) => (
                <option key={r} value={r}>
                  {r}
                </option>
              ))}
            </select>
          </div>

          {/* Mandatory Remarks Textarea */}
          <div className="space-y-1.5">
            <label htmlFor="deactivation-remarks" className="block text-xs font-semibold uppercase tracking-wider text-gray-700">
              Mandatory Remarks &amp; Clearance Notes <span className="text-red-500">*</span>
            </label>
            <textarea
              id="deactivation-remarks"
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              rows={3}
              required
              placeholder="State the detailed justification, clearance verification status, or exit notes (required)..."
              className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-xs text-gray-900 placeholder:text-gray-400 shadow-xs focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
            />
            <p className="text-[11px] text-gray-500">
              Explain why this profile should be formally queued for archiving and locking.
            </p>
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
              disabled={mutation.isPending || !remarks.trim()}
              className="inline-flex items-center gap-1.5 rounded-lg bg-amber-600 px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-amber-700 disabled:opacity-50 transition cursor-pointer"
            >
              {mutation.isPending ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  Submitting Request...
                </>
              ) : (
                <>
                  <FileText className="h-3.5 w-3.5" />
                  Submit Deactivation Request
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
