// components/hr-emploc/ReviewApproveModal.tsx
"use client";

import { useState } from "react";
import {
  CheckCircle2,
  Loader2,
  AlertCircle,
  FileCheck,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  approveHrEmplocReview,
  type HrEmplocListItem,
} from "@/lib/queries/hr_emploc";

type ReviewApproveModalProps = {
  isOpen: boolean;
  onClose: () => void;
  row: HrEmplocListItem | null;
  onSuccess: (message: string) => void;
};

export function ReviewApproveModal({
  isOpen,
  onClose,
  row,
  onSuccess,
}: ReviewApproveModalProps) {
  const [remarks, setRemarks] = useState("");
  const [isApproving, setIsApproving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen || !row) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsApproving(true);
    setError(null);

    try {
      const resolvedKeys = row.deficiencyIssues?.map((i) => i.code) ?? [];
      await approveHrEmplocReview({
        hrEmplocId: row.id,
        resolvedKeys,
        remarks: remarks.trim() || undefined,
      });

      onSuccess(`Correction for "${row.applicantName}" approved and moved to Ready.`);
      handleClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to approve correction review.");
    } finally {
      setIsApproving(false);
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
      title="Approve Correction"
      maxWidthClass="max-w-md"
      disableBackdropClick={true}
      isSubmitting={isApproving}
      isDirty={Boolean(remarks.trim())}
    >
      <div className="space-y-4">
        <div className="flex items-center gap-2.5 pb-2 border-b border-border-subtle">
          <div className="p-2 rounded-lg bg-surface-muted text-brand-primary border border-border-subtle">
            <FileCheck className="h-5 w-5" />
          </div>
          <div>
            <h4 className="text-sm font-semibold text-text-primary">
              Compliance Verification
            </h4>
            <p className="text-xs text-text-muted mt-0.5">
              Confirm compliance and advance to Ready.
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
          {row.deficiencySummary && (
            <div className="flex justify-between">
              <span className="text-text-muted">Deficiencies:</span>
              <span className="font-medium text-text-primary text-right">{row.deficiencySummary}</span>
            </div>
          )}
          {row.notes && (
            <div className="border-t border-border-subtle pt-2 flex flex-col gap-0.5">
              <span className="text-text-muted font-medium">HRCO Remarks:</span>
              <span className="text-text-primary italic">&ldquo;{row.notes}&rdquo;</span>
            </div>
          )}
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <div className="flex items-center gap-2 rounded-lg bg-[var(--danger-bg)] text-[var(--danger-text)] border border-[var(--danger-border)] p-3 text-xs">
              <AlertCircle className="h-4 w-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <div className="space-y-1.5">
            <label
              htmlFor="approval-remarks"
              className="text-xs font-semibold text-text-primary"
            >
              Approval Remarks (Optional)
            </label>
            <textarea
              id="approval-remarks"
              rows={2}
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              placeholder="Optional confirmation note or audit remarks..."
              className="w-full rounded-md border border-border-default bg-surface p-2.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-none focus:ring-1 focus:ring-brand-primary"
              disabled={isApproving}
            />
          </div>

          <div className="flex items-center justify-end gap-2.5 border-t border-border-subtle pt-3">
            <button
              type="button"
              onClick={handleClose}
              disabled={isApproving}
              className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-semibold text-text-primary hover:bg-surface-hover transition cursor-pointer disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isApproving}
              className="inline-flex items-center gap-1.5 rounded-md bg-brand-button px-4 py-1.5 text-xs font-semibold text-white hover:bg-brand-primary-hover transition cursor-pointer disabled:opacity-50"
            >
              {isApproving ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  <span>Approving...</span>
                </>
              ) : (
                <>
                  <CheckCircle2 className="h-3.5 w-3.5" />
                  <span>Approve & Move to Ready</span>
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </Modal>
  );
}
