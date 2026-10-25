// components/hr-emploc/ReviewRevertModal.tsx
"use client";

import { useState } from "react";
import {
  RotateCcw,
  Loader2,
  AlertCircle,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  revertHrEmplocReview,
  type HrEmplocListItem,
} from "@/lib/queries/hr_emploc";

type ReviewRevertModalProps = {
  isOpen: boolean;
  onClose: () => void;
  row: HrEmplocListItem | null;
  onSuccess: (message: string) => void;
};

export function ReviewRevertModal({
  isOpen,
  onClose,
  row,
  onSuccess,
}: ReviewRevertModalProps) {
  const [remarks, setRemarks] = useState("");
  const [isReverting, setIsReverting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen || !row) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = remarks.trim();
    if (!trimmed) {
      setError("Please explain what the HRCO must correct before resubmitting.");
      return;
    }

    setIsReverting(true);
    setError(null);

    try {
      await revertHrEmplocReview({
        hrEmplocId: row.id,
        remarks: trimmed,
      });

      onSuccess(`Record for "${row.applicantName}" returned to Correction queue.`);
      handleClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to revert record to correction.");
    } finally {
      setIsReverting(false);
    }
  };

  const handleClose = () => {
    setRemarks("");
    setError(null);
    onClose();
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Revert to Correction"
      maxWidthClass="max-w-md"
      disableBackdropClick={true}
      isSubmitting={isReverting}
      isDirty={Boolean(remarks.trim())}
    >
      <div className="space-y-4">
        <div className="flex items-center gap-2.5 pb-2 border-b border-border-subtle">
          <div className="p-2 rounded-lg bg-[var(--danger-bg)] text-[var(--danger-text)] border border-[var(--danger-border)]">
            <RotateCcw className="h-5 w-5" />
          </div>
          <div>
            <h4 className="text-sm font-semibold text-text-primary">
              Return to Correction Queue
            </h4>
            <p className="text-xs text-text-muted mt-0.5">
              Return candidate record back to HRCO for correction.
            </p>
          </div>
        </div>

        <div className="rounded-lg bg-surface-muted p-3 space-y-2 border border-border-subtle text-xs">
          <div className="flex justify-between">
            <span className="text-text-muted">Applicant:</span>
            <span className="font-semibold text-text-primary">{row.applicantName}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-text-muted">Account:</span>
            <span className="font-medium text-text-primary">{row.accountName ?? "--"}</span>
          </div>
          {row.notes && (
            <div className="border-t border-border-subtle pt-2 flex flex-col gap-0.5">
              <span className="text-text-muted font-medium">HRCO Remarks Submitted:</span>
              <span className="text-text-primary italic">&ldquo;{row.notes}&rdquo;</span>
            </div>
          )}
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <div className="flex items-center gap-2 rounded-lg bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger-text)] border border-[var(--danger-border)]">
              <AlertCircle className="h-4 w-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <div className="space-y-1.5">
            <label
              htmlFor="revert-remarks"
              className="text-xs font-semibold text-text-primary"
            >
              HR Remarks / Correction Requirements <span className="text-[var(--danger-text)]">*</span>
            </label>
            <textarea
              id="revert-remarks"
              rows={3}
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              placeholder="Explain what HRCO must correct before resubmitting..."
              className="w-full rounded-md border border-border-default bg-surface p-2.5 text-xs text-text-primary placeholder:text-text-muted focus:border-border-strong focus:outline-none focus:ring-1 focus:ring-border-strong"
              disabled={isReverting}
            />
          </div>

          <div className="flex items-center justify-end gap-2.5 border-t border-border-subtle pt-3">
            <button
              type="button"
              onClick={handleClose}
              disabled={isReverting}
              className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-semibold text-text-primary hover:bg-surface-hover transition cursor-pointer disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isReverting}
              className="inline-flex items-center gap-1.5 rounded-md border border-[var(--danger-border)] bg-[var(--danger-bg)] px-4 py-1.5 text-xs font-semibold text-[var(--danger-text)] hover:opacity-90 transition cursor-pointer disabled:opacity-50"
            >
              {isReverting ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  <span>Reverting...</span>
                </>
              ) : (
                <>
                  <RotateCcw className="h-3.5 w-3.5" />
                  <span>Revert to Correction</span>
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </Modal>
  );
}
