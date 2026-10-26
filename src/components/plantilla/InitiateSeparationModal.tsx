"use client";

import { useState } from "react";
import { AlertCircle, Calendar, DoorOpen, Loader2 } from "lucide-react";
import {
  useUpdateSeparationStatus,
  type SeparationStatusType,
} from "@/lib/queries/plantilla";
import { Modal } from "@/components/shared/Modal";

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

  const isDirty = remarks.trim() !== "" || separationType !== "Resigned";

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
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Mark Personnel Separation"
      subtitle={
        <span className="font-mono text-text-secondary text-xs">
          {employeeNo} • {employeeName}
        </span>
      }
      icon={DoorOpen}
      isSubmitting={mutation.isPending}
      isDirty={isDirty}
      maxWidthClass="max-w-lg"
    >
      <form onSubmit={handleSubmit} className="space-y-5">
        {/* Slot vacation warning notice */}
        <div className="rounded-lg border border-border-default bg-surface-muted p-3.5 flex items-start gap-3">
          <AlertCircle className="h-5 w-5 shrink-0 text-text-secondary mt-0.5" />
          <div className="text-xs text-text-primary leading-relaxed">
            <span className="font-semibold text-text-primary">ADR-001 Slot Vacation Notice:</span>
            <p className="mt-0.5 text-text-secondary">
              Initiating separation will transition this employee to Inactive status and automatically
              vacate their workforce slot at <strong className="text-text-primary">{storeName || "Primary Store"}</strong>
              {positionTitle ? ` (${positionTitle})` : ""}. Under ADR-001 Slot-First Architecture,
              the slot remains intact and returns to the recruitment vacancy queue.
            </p>
          </div>
        </div>

        {/* Separation Type Selector */}
        <div className="space-y-1.5">
          <label htmlFor="separation-type" className="block text-xs font-semibold uppercase tracking-wider text-text-secondary">
            Separation Type <span className="text-danger-text">*</span>
          </label>
          <select
            id="separation-type"
            value={separationType}
            onChange={(e) => setSeparationType(e.target.value as SeparationStatusType)}
            className="w-full rounded-lg border border-border-default bg-surface px-3 py-2 text-xs text-text-primary shadow-xs focus:border-brand-primary focus:outline-hidden"
          >
            {SEPARATION_TYPES.map((t) => (
              <option key={t.value} value={t.value}>
                {t.label}
              </option>
            ))}
          </select>
          <p className="text-[11px] text-text-secondary">
            {SEPARATION_TYPES.find((t) => t.value === separationType)?.description}
          </p>
        </div>

        {/* Effective Date Picker */}
        <div className="space-y-1.5">
          <label htmlFor="effective-date" className="block text-xs font-semibold uppercase tracking-wider text-text-secondary">
            Effective Date <span className="text-danger-text">*</span>
          </label>
          <div className="relative">
            <input
              id="effective-date"
              type="date"
              value={effectiveDate}
              onChange={(e) => setEffectiveDate(e.target.value)}
              required
              className="w-full rounded-lg border border-border-default bg-surface px-3 py-2 pl-9 text-xs text-text-primary shadow-xs focus:border-brand-primary focus:outline-hidden"
            />
            <Calendar className="pointer-events-none absolute left-3 top-2.5 h-4 w-4 text-text-muted" />
          </div>
          <p className="text-[11px] text-text-secondary">
            Official date when the employee ceases duties and clears the plantilla slot.
          </p>
        </div>

        {/* Remarks / Reason Textarea */}
        <div className="space-y-1.5">
          <label htmlFor="separation-remarks" className="block text-xs font-semibold uppercase tracking-wider text-text-secondary">
            Reason / Explanatory Remarks
          </label>
          <textarea
            id="separation-remarks"
            value={remarks}
            onChange={(e) => setRemarks(e.target.value)}
            rows={3}
            placeholder="Provide context, exit interview summary, or operational notes..."
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
            className="rounded-lg border border-border-default bg-surface px-4 py-2 text-xs font-medium text-text-secondary hover:bg-surface-hover hover:text-text-primary disabled:opacity-50 transition-colors cursor-pointer"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={mutation.isPending}
            className="inline-flex items-center gap-1.5 rounded-lg bg-danger-bg hover:bg-danger-bg/80 text-danger-text border border-danger-border px-4 py-2 text-xs font-semibold shadow-xs disabled:opacity-50 transition-colors cursor-pointer"
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
    </Modal>
  );
}
