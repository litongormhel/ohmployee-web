"use client";

import { useState } from "react";
import { AlertCircle, Clock, FileText, Loader2, ShieldAlert } from "lucide-react";
import { useCreateDeactivationRequest } from "@/lib/queries/plantilla";
import { Modal } from "@/components/shared/Modal";

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

  const isDirty = remarks.trim() !== "" || reason !== DEACTIVATION_REASONS[0];

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
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Request Personnel Deactivation"
      subtitle={
        <span className="font-mono text-text-secondary text-xs">
          {employeeNo} • {employeeName} • Status: {currentStatus || "Inactive"}
        </span>
      }
      icon={ShieldAlert}
      isSubmitting={mutation.isPending}
      isDirty={isDirty}
      maxWidthClass="max-w-lg"
    >
      <form onSubmit={handleSubmit} className="space-y-5">
        {/* 15-day clearance policy notice */}
        <div className="rounded-lg border border-border-default bg-surface-muted p-3.5 flex items-start gap-3">
          <Clock className="h-5 w-5 shrink-0 text-text-secondary mt-0.5" />
          <div className="text-xs text-text-primary leading-relaxed">
            <span className="font-semibold text-text-primary">Standard 15-Day Clearance Notice:</span>
            <p className="mt-0.5 text-text-secondary">
              Standard operating policy mandates a 15-day clearance and asset recovery window before final
              Super Admin / Head Admin deactivation approval. Submitting this request places the personnel
              record in the <strong className="text-text-primary">Approvals Center</strong> queue.
            </p>
          </div>
        </div>

        {/* Deactivation Reason Category */}
        <div className="space-y-1.5">
          <label htmlFor="deactivation-reason" className="block text-xs font-semibold text-text-secondary">
            Deactivation Justification <span className="text-danger-text">*</span>
          </label>
          <select
            id="deactivation-reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            className="w-full rounded-lg border border-border-default bg-surface px-3 py-2 text-xs text-text-primary shadow-xs focus:border-brand-primary focus:outline-hidden"
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
          <label htmlFor="deactivation-remarks" className="block text-xs font-semibold text-text-secondary">
            Mandatory Remarks &amp; Clearance Notes <span className="text-danger-text">*</span>
          </label>
          <textarea
            id="deactivation-remarks"
            value={remarks}
            onChange={(e) => setRemarks(e.target.value)}
            rows={3}
            required
            placeholder="State the detailed justification, clearance verification status, or exit notes (required)..."
            className="w-full rounded-lg border border-border-default bg-surface px-3 py-2 text-xs text-text-primary placeholder:text-text-muted shadow-xs focus:border-brand-primary focus:outline-hidden"
          />
          <p className="text-[11px] text-text-secondary">
            Explain why this profile should be formally queued for archiving and locking.
          </p>
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
            disabled={mutation.isPending || !remarks.trim()}
            className="inline-flex items-center gap-1.5 rounded-lg bg-brand-button px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-brand-button-hover disabled:bg-surface-muted disabled:text-text-secondary disabled:border-border-default disabled:cursor-not-allowed disabled:shadow-none transition-colors cursor-pointer"
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
    </Modal>
  );
}
