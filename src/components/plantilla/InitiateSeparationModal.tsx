"use client";

import { useState } from "react";
import { AlertCircle, Calendar, DoorOpen, Loader2, X } from "lucide-react";
import {
  useUpdateSeparationStatus,
  type SeparationStatusType,
} from "@/lib/queries/plantilla";

export interface InitiateSeparationModalProps {
  isOpen: boolean;
  onClose: () => void;
  plantillaId: string;
  employeeName: string;
  employeeNo: string;
  positionTitle?: string | null;
  storeName?: string | null;
  onSuccess?: () => void;
}

const SEPARATION_TYPES: { value: SeparationStatusType; label: string; description: string }[] = [
  { value: "Resigned", label: "Resigned", description: "Voluntary resignation submitted by employee" },
  { value: "Endo", label: "Endo (End of Contract)", description: "Fixed-term contractual deployment completed" },
  { value: "Terminated", label: "Terminated", description: "Involuntary termination due to administrative / disciplinary grounds" },
  { value: "AWOL", label: "AWOL (Absence Without Official Leave)", description: "Unexcused abandonment of post without notice" },
  { value: "Others", label: "Others", description: "Other authorized separation reason" },
];

export function InitiateSeparationModal({
  isOpen,
  onClose,
  plantillaId,
  employeeName,
  employeeNo,
  positionTitle,
  storeName,
  onSuccess,
}: InitiateSeparationModalProps) {
  const [separationType, setSeparationType] = useState<SeparationStatusType>("Resigned");
  const [effectiveDate, setEffectiveDate] = useState<string>(
    () => new Date().toISOString().substring(0, 10),
  );
  const [remarks, setRemarks] = useState<string>("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const mutation = useUpdateSeparationStatus();

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!effectiveDate) {
      setErrorMessage("Please select an effective separation date.");
      return;
    }

    mutation.mutate(
      {
        plantillaId,
        separationStatus: separationType,
        effectiveDate,
        remarks: remarks.trim() || undefined,
        openVacancy: true,
      },
      {
        onSuccess: () => {
          onSuccess?.();
          onClose();
        },
        onError: (err) => {
          setErrorMessage(err.message || "Failed to initiate employee separation.");
        },
      },
    );
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="separation-modal-title"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-in fade-in duration-150"
    >
      <div className="relative w-full max-w-lg rounded-xl border border-gray-200 bg-white shadow-2xl overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4 bg-red-50/70">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-red-100 text-red-700 border border-red-200">
              <DoorOpen className="h-5 w-5" />
            </div>
            <div>
              <h2 id="separation-modal-title" className="text-base font-semibold text-gray-900">
                Mark Personnel Separation
              </h2>
              <p className="text-xs text-gray-500 font-mono">
                {employeeNo} &bull; {employeeName}
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
          {/* Slot vacation warning notice */}
          <div className="rounded-lg border border-amber-200 bg-amber-50/80 p-3.5 flex items-start gap-3">
            <AlertCircle className="h-5 w-5 shrink-0 text-amber-600 mt-0.5" />
            <div className="text-xs text-amber-900 leading-relaxed">
              <span className="font-semibold">ADR-001 Slot Vacation Notice:</span>
              <p className="mt-0.5 text-amber-800">
                Initiating separation will transition this employee to Inactive status and automatically
                vacate their workforce slot at <strong>{storeName || "Primary Store"}</strong>
                {positionTitle ? ` (${positionTitle})` : ""}. Under ADR-001 Slot-First Architecture,
                the slot remains intact and returns to the recruitment vacancy queue.
              </p>
            </div>
          </div>

          {/* Separation Type Selector */}
          <div className="space-y-1.5">
            <label htmlFor="separation-type" className="block text-xs font-semibold uppercase tracking-wider text-gray-700">
              Separation Type <span className="text-red-500">*</span>
            </label>
            <select
              id="separation-type"
              value={separationType}
              onChange={(e) => setSeparationType(e.target.value as SeparationStatusType)}
              className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-xs text-gray-900 shadow-xs focus:border-red-500 focus:outline-none focus:ring-1 focus:ring-red-500"
            >
              {SEPARATION_TYPES.map((t) => (
                <option key={t.value} value={t.value}>
                  {t.label}
                </option>
              ))}
            </select>
            <p className="text-[11px] text-gray-500">
              {SEPARATION_TYPES.find((t) => t.value === separationType)?.description}
            </p>
          </div>

          {/* Effective Date Picker */}
          <div className="space-y-1.5">
            <label htmlFor="effective-date" className="block text-xs font-semibold uppercase tracking-wider text-gray-700">
              Effective Date <span className="text-red-500">*</span>
            </label>
            <div className="relative">
              <input
                id="effective-date"
                type="date"
                value={effectiveDate}
                onChange={(e) => setEffectiveDate(e.target.value)}
                required
                className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 pl-9 text-xs text-gray-900 shadow-xs focus:border-red-500 focus:outline-none focus:ring-1 focus:ring-red-500"
              />
              <Calendar className="pointer-events-none absolute left-3 top-2.5 h-4 w-4 text-gray-400" />
            </div>
            <p className="text-[11px] text-gray-500">
              Official date when the employee ceases duties and clears the plantilla slot.
            </p>
          </div>

          {/* Remarks / Reason Textarea */}
          <div className="space-y-1.5">
            <label htmlFor="separation-remarks" className="block text-xs font-semibold uppercase tracking-wider text-gray-700">
              Reason / Explanatory Remarks
            </label>
            <textarea
              id="separation-remarks"
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              rows={3}
              placeholder="Provide context, exit interview summary, or operational notes..."
              className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-xs text-gray-900 placeholder:text-gray-400 shadow-xs focus:border-red-500 focus:outline-none focus:ring-1 focus:ring-red-500"
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
              className="inline-flex items-center gap-1.5 rounded-lg bg-red-600 px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-red-700 disabled:opacity-50 transition cursor-pointer"
            >
              {mutation.isPending ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  Processing Separation...
                </>
              ) : (
                "Confirm Separation & Vacate Slot"
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
